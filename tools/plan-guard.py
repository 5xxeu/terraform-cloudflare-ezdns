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
        raise SystemExit(f"plan-guard: cannot read the plan {path}: {e}") from None


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
    return module is None or address.startswith(module + ".")


def allowed(address, patterns):
    """Whether an address matches one of the patterns, where * stands for any characters
    (brackets and quotes match themselves, as they are in every resource address)."""
    return any(re.fullmatch(".*".join(re.escape(part) for part in p.split("*")), address) for p in patterns)


def check(plan, args):
    """Returns the list of problems of the plan (empty: the plan passes)."""
    deletes, replacements, proxy_off, unknown_proxy = [], [], [], []
    # Record sets after the apply: (fqdn, type) -> number of records
    after_sets = {}

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

        if actions != ["delete"] and after:
            # cloudflare_record (provider v4) has the fully qualified name in hostname
            key = (fqdn(after.get("name"), args.zone), str(after.get("type", "")).upper())
            after_sets[key] = after_sets.get(key, 0) + 1

        if allowed(address, args.allow):
            continue
        if actions == ["delete"]:
            deletes.append(address)
        elif "delete" in actions and "create" in actions:
            replacements.append(address)
        if before.get("proxied") is True and "delete" not in actions:
            if after_unknown.get("proxied"):
                unknown_proxy.append(address)
            elif after.get("proxied") is not True:
                proxy_off.append(address)

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

    for spec in args.require:
        parts = spec.split(":")
        if len(parts) not in (2, 3) or not parts[0] or not parts[1]:
            raise SystemExit(f"plan-guard: --require {spec!r} is not NAME:TYPE[:MIN]")
        try:
            minimum = int(parts[2]) if len(parts) == 3 else 1
        except ValueError:
            raise SystemExit(f"plan-guard: --require {spec!r}: MIN is not a number") from None
        key = (fqdn(parts[0], args.zone), parts[1].upper())
        count = after_sets.get(key, 0)
        if count < minimum:
            problems.append(f"{key[1]} records of {key[0]}: {count} after the apply, at least {minimum} required")
    return problems


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    plan = load_plan(args.plan)
    if not isinstance(plan, dict) or "format_version" not in plan:
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
