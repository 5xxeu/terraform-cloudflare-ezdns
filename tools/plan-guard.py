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
import json
import re
import sys

RECORD_TYPES = ("cloudflare_dns_record", "cloudflare_record")


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


def check(plan, args):
    """Returns the list of problems of the plan (empty: the plan passes)."""
    deletes, replacements, proxy_off, unknown_proxy = [], [], [], []
    # Record sets after the apply: (fqdn, type) -> number of records
    after_sets = {}
    # Zones of the records of the plan, to catch a --require over several zones
    zones = set()
    # Proxied records that leave their name (deleted, or moved by an update), and records
    # that arrive on a name (created, or moved there): a new key (a changed value without
    # a key) deletes the record and creates another one, which must stay proxied too
    deleted_proxied, created = [], []

    for rc in plan.get("resource_changes", []):
        if rc.get("mode") != "managed" or rc.get("type") not in RECORD_TYPES:
            continue
        address = rc.get("address", "")
        if not in_module(address, args.module):
            continue
        change = rc.get("change", {})
        actions = change.get("actions", [])
        before = change.get("before") or {}
        after = change.get("after") or {}
        after_unknown = change.get("after_unknown") or {}

        # A record counts for its set only if its name and type are known at plan: a name
        # computed at apply could end up anywhere (and a missing name is not the apex)
        if actions != ["delete"] and after and not after_unknown.get("name") and not after_unknown.get("type") \
                and after.get("name") and after.get("type") \
                and (args.zone_id is None or (after.get("zone_id") == args.zone_id and not after_unknown.get("zone_id"))):
            key = (fqdn(after.get("name"), args.zone), str(after.get("type")).upper())
            after_sets[key] = after_sets.get(key, 0) + 1
        zones.update(v.get("zone_id") for v in (before, after) if v.get("zone_id"))
        if after_unknown.get("zone_id"):
            zones.add("unknown")

        # Collected before the exceptions: allowing a delete does not allow a new record
        # on the same name to come back unproxied
        if before.get("proxied") is True and (actions == ["delete"] or (after and moved(before, after, after_unknown, args.zone))):
            deleted_proxied.append(before)
        if allowed(address, args.allow):
            continue
        if actions != ["delete"] and after and (not before or moved(before, after, after_unknown, args.zone)):
            created.append((address, after, after_unknown))
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
    # unproxied A on the same name publishes the address just the same
    for address, after, after_unknown in created:
        if after.get("proxied") is True or address in proxy_off or address in unknown_proxy:
            continue
        if not after_unknown.get("type") and str(after.get("type", "")).upper() not in ("A", "AAAA", "CNAME"):
            continue
        for before in deleted_proxied:
            if (after_unknown.get("zone_id") or before.get("zone_id") == after.get("zone_id")) \
                    and (after_unknown.get("name") or same_name(before.get("name"), after.get("name"), args.zone)):
                (unknown_proxy if after_unknown.get("proxied") else proxy_off).append(address)
                break

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
    if unknown_proxy and not args.allow_proxy_disable:
        problems.append("Whether these proxied records stay proxied is not known until apply:")
        problems += [f"  {a}" for a in unknown_proxy]

    if args.require and args.zone_id is None and len(zones) > 1:
        problems.append("The plan has records of several zones, so --require cannot tell them apart: give --zone-id")
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
    problems = check(plan, args)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("plan-guard: the plan passes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
