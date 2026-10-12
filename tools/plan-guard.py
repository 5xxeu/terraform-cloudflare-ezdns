#!/usr/bin/env python3
"""Check a saved Terraform plan for risky DNS record changes before it is applied.

The module validates the records it is given, but it cannot see what a plan does to the
records that are already in the state: a lost YAML file, a renamed key or a removed
module call deletes records, and the configuration is still valid. This script reads the
JSON form of a saved plan and fails when the plan deletes or replaces records, turns off
the Cloudflare proxy, or leaves a required record set (such as the MX records of the
zone) empty, unless the change is allowed explicitly.

    terraform plan -out=tfplan
    terraform show -json tfplan > tfplan.json
    python3 plan-guard.py tfplan.json --zone example.com --require @:MX --require @:A

Only DNS record resources (cloudflare_dns_record, cloudflare_record) are checked; the
other resources of the plan are ignored. Exit status: 0 when the plan passes, 1 when it
does not, 2 when the plan cannot be read. Python 3.8 or later, standard library only.
"""

import argparse
import ipaddress
import json
import re
import sys

RECORD_TYPES = ("cloudflare_dns_record", "cloudflare_record")
# The actions of a change in a plan (terraform show -json)
ACTIONS = {"no-op", "create", "read", "update", "delete", "forget"}


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Check a saved Terraform plan (terraform show -json) for risky DNS record changes.",
    )
    parser.add_argument("plan", help="JSON plan from terraform show -json, or - for standard input")
    parser.add_argument("--max-deletes", type=int, default=0, metavar="N",
                        help="records the plan may delete (default 0; replacements are counted separately)")
    parser.add_argument("--max-replacements", type=int, default=0, metavar="N",
                        help="records the plan may replace, deleting and creating them again (default 0)")
    parser.add_argument("--allow-proxy-disable", action="store_true",
                        help="allow records that are proxied now to become unproxied, which publishes their origin address")
    parser.add_argument("--allow", action="append", default=[], metavar="ADDRESS",
                        help="resource address whose changes are not checked, * matches any characters "
                             "(e.g. 'module.dns.*[\"www A *\"]'); repeat for more")
    parser.add_argument("--require", action="append", default=[], metavar="NAME:TYPE[:MIN]",
                        help="record set that must have at least MIN records (default 1) after the apply, "
                             "e.g. @:MX or www:CNAME; NAME as in the records input; needs --zone; repeat for more")
    parser.add_argument("--zone", metavar="NAME", help="zone name, to qualify the names of --require and of the records")
    parser.add_argument("--zone-id", metavar="ID",
                        help="only count records of this zone for --require; needed when the plan has records of several zones")
    parser.add_argument("--module", metavar="ADDRESS",
                        help="only check records of this module call and the modules in it (e.g. module.dns)")
    args = parser.parse_args(argv)
    if args.require and not args.zone:
        parser.error("--require needs --zone")
    return args


def load_plan(path):
    try:
        if path == "-":
            return json.load(sys.stdin)
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        fail(f"cannot read the plan {path}: {e}")


def fail(message):
    """Stops with exit code 2: the input or the arguments are wrong (1 means the plan fails)."""
    print(f"plan-guard: {message}", file=sys.stderr)
    raise SystemExit(2)


def fqdn(name, zone):
    """The fully qualified name in lower case, without a trailing dot."""
    name = (name or "").rstrip(".").lower()
    zone = (zone or "").rstrip(".").lower()
    if not zone:
        return name
    if name in ("@", ""):
        return zone
    if name == zone or name.endswith("." + zone):
        return name
    return f"{name}.{zone}"


def in_module(address, module):
    """Whether the resource is in the module call or in a module in it; a call with count
    or for_each has an instance key (module.dns[0], module.dns["prod"]), which matches
    unless the instance is given (module.dns["prod"] matches only that instance)."""
    return module is None or address.startswith(module + ".") or (not module.endswith("]") and address.startswith(module + "["))


def allowed(address, patterns):
    """Whether an address matches one of the patterns, where * stands for any characters
    (brackets and quotes match themselves, as they are in every resource address)."""
    return any(re.fullmatch(".*".join(re.escape(part) for part in p.split("*")), address) for p in patterns)


def same_name(a, b, zone):
    """Whether two record names may be the same name: fully qualified with --zone; without
    it, a name as written (www) also matches the fully qualified one (www.example.com),
    and the apex (@) matches every name, as the zone name is not known."""
    a, b = fqdn(a, zone), fqdn(b, zone)
    if not zone and (a in ("@", "") or b in ("@", "")):
        return True
    return a == b or (not zone and (a.startswith(b + ".") or b.startswith(a + ".")))


def moved(before, after, after_unknown, zone):
    """Whether a record that existed is on another name or zone after the apply (or may be)."""
    return bool(after_unknown.get("name") or after_unknown.get("zone_id")
                or before.get("zone_id") != after.get("zone_id")
                or fqdn(before.get("name"), zone) != fqdn(after.get("name"), zone))


def hidden_value(record):
    """The value of an A, AAAA or CNAME record in a normal form (addresses canonical,
    names in lower case without the trailing dot), or None for other records."""
    rtype, content = str(record.get("type", "")).upper(), record.get("content")
    if rtype not in ("A", "AAAA", "CNAME") or not isinstance(content, str):
        return None
    if rtype == "CNAME":
        return "CNAME " + content.rstrip(".").lower()
    try:
        return "IP " + ipaddress.ip_address(content).compressed
    except ValueError:
        return "IP " + content.lower()


# One word of the text of service parameters: a key with an optional value, in quotes or
# not (the priority and the target in content are words without a value)
SVC_PARAM = re.compile(r'\s*([^\s="]+)(?:=("(?:[^"\\]|\\.)*"|[^\s"]*))?')
LOOSE_HINT = re.compile(r'(?:ipv4hint|ipv6hint)="?([^"\s]*)', re.IGNORECASE)


def data_items(data):
    """The data of a record as a list: an object in provider 5.x, a list of one in 4.x."""
    return data if isinstance(data, list) else [data]


def data_values(record):
    """The texts of service parameters in data.value of a record."""
    return [d.get("value") for d in data_items(record.get("data")) if isinstance(d, dict) and isinstance(d.get("value"), str)]


def svcb_type(record, unknown):
    """Whether a record is (or, with its type known only after apply, may be) HTTPS or SVCB."""
    return bool(unknown.get("type")) or str(record.get("type", "")).upper() in ("HTTPS", "SVCB")


def hints(record, unknown=None):
    """The addresses in the ipv4hint and ipv6hint parameters of an HTTPS or SVCB record,
    in the form of hidden_value (they are in data.value, and in content in provider 5.x).
    Only whole parameters count, not the text of another one (alpn="ipv4hint=...")."""
    if not svcb_type(record, unknown or {}):
        return set()
    addresses = set()
    for text in data_values(record) + [record.get("content")]:
        pos = 0
        while isinstance(text, str):
            m = SVC_PARAM.match(text, pos)
            if not m or m.end() == pos:
                # Text that does not parse (a quote that is not closed): any hint in the rest
                # counts, as Cloudflare may read it otherwise
                for value in LOOSE_HINT.findall(text[pos:]):
                    addresses.update(hidden_value({"type": "A", "content": a.strip()}) for a in value.split(",") if a.strip())
                break
            pos = m.end()
            if m.group(1).lower() in ("ipv4hint", "ipv6hint") and m.group(2):
                value = re.sub(r"\\(.)", r"\1", m.group(2).strip('"'))
                addresses.update(hidden_value({"type": "A", "content": a.strip()}) for a in value.split(",") if a.strip())
    return addresses


def hints_unknown(record, unknown):
    """Whether the service parameters of an HTTPS or SVCB record are known only after apply:
    data.value is, or content is and the record has no data (provider 5.x computes content
    from data, so a known data is enough to check, also one without a value)."""
    return svcb_type(record, unknown) and (
        any(d is True or (isinstance(d, dict) and d.get("value")) for d in data_items(unknown.get("data")))
        or (bool(unknown.get("content")) and not any(isinstance(d, dict) for d in data_items(record.get("data")))))


def value_kinds(record, unknown):
    """The kinds of value an A, AAAA or CNAME record can have: both when its type is
    known only after apply."""
    if unknown.get("type"):
        return ["IP ", "CNAME "]
    rtype = str(record.get("type", "")).upper()
    return ["CNAME "] if rtype == "CNAME" else ["IP "] if rtype in ("A", "AAAA") else []


def published(before, after, after_unknown, zone):
    """Whether the record published the same unproxied value on the same name before the
    plan, so the apply publishes nothing new (another type, content, name or zone does)."""
    return bool(before) and before.get("proxied") is False and not moved(before, after, after_unknown, zone) \
        and not after_unknown.get("type") and not after_unknown.get("content") \
        and str(before.get("type", "")).upper() == str(after.get("type", "")).upper() \
        and before.get("content") == after.get("content")


def check(plan, args):
    """Returns the list of problems of the plan (empty: the plan passes)."""
    deletes, replacements, proxy_off, unknown_proxy, unknown_value = [], [], [], [], []
    # Record sets after the apply: (fqdn, type) -> number of records
    after_sets = {}
    # Zones of the records of the plan, to catch a --require over several zones
    zones = set()
    # Proxied records that leave their name (deleted, moved by an update, or no longer
    # proxied), and records that arrive on a name (created, or moved there): a new key (a
    # changed value without a key) deletes the record and creates another one, which must
    # stay proxied too
    deleted_proxied, created = [], []
    # Proxied A, AAAA and CNAME records that exist and stay through the apply: while a name
    # has one, Cloudflare answers with its own addresses for the name, also for the
    # unproxied records on it. A created or replaced record does not count: Terraform may
    # delete the old record first, and the name is unhidden until the new one exists
    remaining_proxied = []
    # The values that proxied records hide (the addresses and names of origins), before
    # or after the apply: an unproxied record with one of them publishes the origin
    # under any name, also in another zone
    hidden = {}
    # The kinds of values ("IP ", "CNAME ") that proxied records hide but that are known
    # only after apply, with whether one of them is in the module
    hidden_unknown = {}
    # HTTPS and SVCB records that get new addresses in ipv4hint or ipv6hint (or hints known
    # only after apply): a hidden address there publishes the origin as an unproxied A does
    hinted, hint_leaks = [], []

    # --zone qualifies the names of one zone: of --zone-id, or of a plan with one zone.
    # Names of other zones are compared without it (a name as written also matches the
    # fully qualified one, the apex every name), which may flag more but misses nothing
    record_changes = [rc for rc in plan.get("resource_changes", [])
                      if rc.get("mode") == "managed" and rc.get("type") in RECORD_TYPES]
    plan_zones = set()
    for rc in record_changes:
        change = rc.get("change", {})
        for side in (change.get("before") or {}, change.get("after") or {}):
            plan_zones.add(side.get("zone_id"))
        if (change.get("after_unknown") or {}).get("zone_id"):
            plan_zones.add("unknown")
    plan_zones.discard(None)

    def zone_of(record):
        if args.zone_id is not None:
            return args.zone if record.get("zone_id") == args.zone_id else None
        return args.zone if len(plan_zones) <= 1 else None

    for rc in plan.get("resource_changes", []):
        if rc.get("mode") != "managed" or rc.get("type") not in RECORD_TYPES:
            continue
        address = rc.get("address", "")
        change = rc.get("change", {})
        actions = change.get("actions", [])
        before = change.get("before") or {}
        after = change.get("after") or {}
        after_unknown = change.get("after_unknown") or {}
        # A forgotten record (a removed block with destroy = false) stays in Cloudflare as it
        # is and only leaves the state, so for the checks it does not change
        if actions == ["forget"]:
            actions, after, after_unknown = ["no-op"], before, {}

        # Records outside --module are checked only as neighbours on the names of the
        # records of the module (and the other way round): the proxy hides a whole name,
        # whichever module call manages its records
        # A record moved out of the module (a moved block) still belongs to it
        own = in_module(address, args.module) or in_module(rc.get("previous_address") or "", args.module)
        # A replacement that deletes first (["delete", "create"]; create_before_destroy gives
        # ["create", "delete"]) leaves the name unhidden until the new record exists
        if before.get("proxied") is True and (actions in (["delete"], ["delete", "create"]) or (after and (
                moved(before, after, after_unknown, zone_of(before)) or after_unknown.get("proxied") or after.get("proxied") is not True))):
            deleted_proxied.append((before, own))
        for side in (before, after):
            if side.get("proxied") is True and hidden_value(side):
                hidden[hidden_value(side)] = hidden.get(hidden_value(side), False) or own
        if after.get("proxied") is True and after_unknown.get("content"):
            for kind in value_kinds(after, after_unknown):
                hidden_unknown[kind] = hidden_unknown.get(kind, False) or own
        if actions in (["no-op"], ["update"]) and before.get("proxied") is True and after.get("proxied") is True \
                and not after_unknown.get("proxied") and not moved(before, after, after_unknown, zone_of(before)) \
                and str(after.get("type", "")).upper() in ("A", "AAAA", "CNAME"):
            remaining_proxied.append(after)
        # destroy = false on a replaced record (["forget", "create"]): the old record stays
        # in Cloudflare as it is, next to the new one
        kept = before if actions == ["forget", "create"] else None
        if kept and kept.get("proxied") is True and str(kept.get("type", "")).upper() in ("A", "AAAA", "CNAME"):
            remaining_proxied.append(kept)
        # An unproxied record that changes (deleted, moved, replaced, a new value, or the
        # proxy turned on) keeps its old value until Terraform gets to it, which may be
        # after the proxied records of the name are gone: that value is a neighbour too
        if before.get("proxied") is False and str(before.get("type", "")).upper() in ("A", "AAAA", "CNAME") \
                and actions not in (["no-op"], ["read"]) \
                and not (after and after.get("proxied") is False and not after_unknown.get("proxied")
                         and published(before, after, after_unknown, zone_of(after))) \
                and not allowed(address, args.allow):
            created.append((address, before, {}, False, own))
        if actions not in (["no-op"], ["read"], ["delete"]) and after and not allowed(address, args.allow):
            new_hints = hints(after, after_unknown) - hints(before)
            if new_hints or hints_unknown(after, after_unknown):
                hinted.append((address, new_hints, hints_unknown(after, after_unknown), own))
        if not own:
            if actions != ["delete"] and after and not allowed(address, args.allow):
                created.append((address, after, after_unknown, not published(before, after, after_unknown, zone_of(after)), False))
            continue

        # A record counts for its set only if its name and type are known at plan: a name
        # computed at apply could end up anywhere (and a missing name is not the apex)
        for rec, unk in ([(after, after_unknown)] if actions != ["delete"] and after else []) + ([(kept, {})] if kept else []):
            if not unk.get("name") and not unk.get("type") and rec.get("name") and rec.get("type") \
                    and (args.zone_id is None or (rec.get("zone_id") == args.zone_id and not unk.get("zone_id"))):
                key = (fqdn(rec.get("name"), args.zone), str(rec.get("type")).upper())
                after_sets[key] = after_sets.get(key, 0) + 1
        zones.update(v.get("zone_id") for v in (before, after) if v.get("zone_id"))
        if after_unknown.get("zone_id"):
            zones.add("unknown")

        # deleted_proxied and remaining_proxied are collected above, before the exceptions:
        # allowing a delete (or turning off the proxy of one record) does not allow the
        # other records of the name to be published
        if allowed(address, args.allow):
            continue
        if actions != ["delete"] and after:
            created.append((address, after, after_unknown, not published(before, after, after_unknown, zone_of(after)), True))
        if actions == ["delete"]:
            deletes.append(address)
        elif "delete" in actions and "create" in actions:
            replacements.append(address)
        # Also a replacement: the record that is created again must stay proxied
        if before.get("proxied") is True and actions != ["delete"]:
            if after_unknown.get("proxied"):
                unknown_proxy.append(address)
            elif after.get("proxied") is not True:
                proxy_off.append(address)

    # Any type that can point at the origin counts: a proxied CNAME replaced by an
    # unproxied A on the same name publishes the address just the same. A record that
    # stays as it was publishes its address only if the name keeps no proxied record
    # (exactly the same name: a name in another form does not count)
    def still_proxied(before):
        return any(r.get("zone_id") == before.get("zone_id") and fqdn(r.get("name"), zone_of(before)) == fqdn(before.get("name"), zone_of(before))
                   for r in remaining_proxied)

    for address, after, after_unknown, new, own in created:
        if after.get("proxied") is True or address in proxy_off or address in unknown_proxy:
            continue
        if not after_unknown.get("type") and str(after.get("type", "")).upper() not in ("A", "AAAA", "CNAME"):
            continue
        # A new unproxied record with the value of a proxied one (a rename that drops the
        # proxy, an origin name next to the proxied one). When the type or a value is known
        # only after apply, a match cannot be ruled out: the record fails as well
        if new:
            kinds = value_kinds(after, after_unknown)
            values = [] if after_unknown.get("content") else [
                hidden_value({**after, "type": "CNAME" if kind == "CNAME " else "A"}) for kind in kinds]
            if any(v in hidden and (own or hidden[v]) for v in values):
                (unknown_proxy if after_unknown.get("proxied") else proxy_off).append(address)
                continue
            if any(kind in hidden_unknown and (own or hidden_unknown[kind]) for kind in kinds) \
                    or (after_unknown.get("content") and any(v.startswith(tuple(kinds)) and (own or o) for v, o in hidden.items())):
                unknown_value.append(address)
                continue
        for before, before_own in deleted_proxied:
            if (own or before_own) and (after_unknown.get("zone_id") or before.get("zone_id") == after.get("zone_id")) \
                    and (after_unknown.get("name") or same_name(before.get("name"), after.get("name"), zone_of(before))) \
                    and (new or not still_proxied(before)):
                (unknown_proxy if after_unknown.get("proxied") else proxy_off).append(address)
                break

    for address, new_hints, unknown, own in hinted:
        if address in proxy_off or address in unknown_proxy or address in unknown_value:
            continue
        if any(v in hidden and (own or hidden[v]) for v in new_hints):
            hint_leaks.append(address)
        elif ("IP " in hidden_unknown and (own or hidden_unknown["IP "])) \
                or (unknown and any(v.startswith("IP ") and (own or o) for v, o in hidden.items())):
            unknown_value.append(address)

    problems = []
    if len(deletes) > args.max_deletes:
        problems.append(f"The plan deletes {len(deletes)} records (allowed: {args.max_deletes}):")
        problems += [f"  {a}" for a in deletes]
    if len(replacements) > args.max_replacements:
        problems.append(f"The plan replaces {len(replacements)} records, deleting them before they are created "
                        f"again (allowed: {args.max_replacements}); give records whose value changes a key:")
        problems += [f"  {a}" for a in replacements]
    if proxy_off and not args.allow_proxy_disable:
        problems.append("The plan turns off the proxy of records, which publishes their origin address "
                        "(--allow-proxy-disable allows it):")
        problems += [f"  {a}" for a in proxy_off]
    if hint_leaks and not args.allow_proxy_disable:
        problems.append("These HTTPS or SVCB records publish the origin address of a proxied record in "
                        "ipv4hint or ipv6hint (--allow-proxy-disable or --allow allows it):")
        problems += [f"  {a}" for a in hint_leaks]
    if unknown_proxy and not args.allow_proxy_disable:
        problems.append("Whether these proxied records stay proxied is not known until apply:")
        problems += [f"  {a}" for a in unknown_proxy]
    if unknown_value and not args.allow_proxy_disable:
        problems.append("These unproxied records may get the hidden origin of a proxied record, as a value or "
                        "a type is known only after apply (--allow-proxy-disable or --allow allows it):")
        problems += [f"  {a}" for a in unknown_value]

    if args.require and args.zone_id is None and len(zones) > 1:
        problems.append("The plan has records of several zones, so --require cannot tell them apart: give --zone-id")
    # Zones known only after apply cannot be told from each other (several new zones are
    # all "unknown"), so the records may belong to any of them
    elif args.require and args.zone_id is None and "unknown" in zones:
        problems.append("The zone of some records is known only after apply, so --require cannot tell which "
                        "zone they are in: apply the zone first, or run without --require")
    for spec in args.require:
        parts = spec.split(":")
        if len(parts) not in (2, 3) or not parts[0] or not parts[1]:
            fail(f"--require {spec!r} is not NAME:TYPE[:MIN]")
        try:
            minimum = int(parts[2]) if len(parts) == 3 else 1
        except ValueError:
            fail(f"--require {spec!r}: MIN is not a number")
        key = (fqdn(parts[0], args.zone), parts[1].upper())
        count = after_sets.get(key, 0)
        if count < minimum:
            problems.append(f"{key[1]} records of {key[0]}: {count} after the apply, at least {minimum} required")
    return problems


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    plan = load_plan(args.plan)
    # planned_values is in every plan, also one without changes (which has no
    # resource_changes); the state (terraform show -json without a plan file) has values
    if not isinstance(plan, dict) or "format_version" not in plan or "planned_values" not in plan:
        print(f"plan-guard: {args.plan} is not a plan in the JSON format of terraform show -json", file=sys.stderr)
        return 2
    changes = plan.get("resource_changes", [])
    if not isinstance(changes, list) or not all(isinstance(rc, dict) for rc in changes):
        print(f"plan-guard: {args.plan}: resource_changes is not a list of changes", file=sys.stderr)
        return 2
    # The changes of records must have the shape of a plan: a wrong one (actions as a
    # string) would not fail below, but skip the change
    for rc in changes:
        if rc.get("type") not in RECORD_TYPES:
            continue
        change = rc.get("change")
        actions = change.get("actions") if isinstance(change, dict) else None
        if not isinstance(actions, list) or not actions or not all(isinstance(a, str) and a in ACTIONS for a in actions) \
                or not all(isinstance(change.get(side), (dict, type(None))) for side in ("before", "after", "after_unknown")):
            print(f"plan-guard: {args.plan}: the change of {rc.get('address')!r} does not have the shape of a plan", file=sys.stderr)
            return 2
    # Any other unexpected shape (a name that is not text, a change that is not an
    # object) is a broken input too, not a failing plan
    try:
        problems = check(plan, args)
    except (AttributeError, KeyError, TypeError, ValueError) as e:
        print(f"plan-guard: {args.plan} has an unexpected structure: {e!r}", file=sys.stderr)
        return 2
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("plan-guard: the plan passes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
