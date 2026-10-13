#!/usr/bin/env python3
"""Propose moved blocks for DNS records that a saved plan deletes and creates again.

A record whose key changes (a key added or renamed, a name written in another form, a
record moved to another module call) gets another Terraform address: without a moved
block, the plan deletes the record and creates the same one again, and the name is
without it in between. This script reads the JSON form of a saved plan, pairs each
deleted record with the created record that is the same DNS record (the same zone,
name, type and value), and writes a moved block for each pair:

    terraform plan -out=tfplan
    terraform show -json tfplan > tfplan.json
    python3 moved-blocks.py tfplan.json --zone example.com > moved.tf

Names are compared fully qualified and in lower case, addresses in their canonical
form, hostnames without the trailing dot. TTL, proxy status, comments and tags are not
a part of what the record is: they change in place after the move. A record that
matches several others (copies of one record), or whose name, type or value is known
only after apply, gets no block; it is listed as a comment to decide by hand. Records
of different resource types (cloudflare_record of provider v4 and cloudflare_dns_record
of v5) are not paired: see the migration in the README for those.

Python 3.8 or later, standard library only. Exit status: 0 when every deleted and
created record is paired or has no counterpart, 1 when some need a choice by hand (the
blocks for the others are written anyway), 2 when the plan cannot be read.
"""

import argparse
import ipaddress
import json
import sys

RECORD_TYPES = ("cloudflare_dns_record", "cloudflare_record")
# Types whose content is a hostname, compared in lower case without the trailing dot
HOSTNAME_TYPES = ("CNAME", "MX", "NS", "PTR")
# Types identified by their content; the others by their data, when they have one
SIMPLE_TYPES = ("A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT")
# Fields of data that hold hostnames or hex strings, compared in lower case
CASE_INSENSITIVE_FIELDS = ("target", "replacement", "digest", "fingerprint")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Propose moved blocks for DNS records that a saved plan (terraform show -json) deletes and creates again.",
    )
    parser.add_argument("plan", help="JSON plan from terraform show -json, or - for standard input")
    parser.add_argument("--zone", required=True, metavar="NAME", help="zone name, to qualify the names of the records")
    return parser.parse_args(argv)


def fail(message):
    print(f"moved-blocks: {message}", file=sys.stderr)
    raise SystemExit(2)


def load_plan(path):
    try:
        if path == "-":
            return json.load(sys.stdin)
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        fail(f"cannot read the plan {path}: {e}")


def fqdn(name, zone):
    name = (name or "").rstrip(".").lower()
    zone = zone.rstrip(".").lower()
    if name in ("@", "", zone):
        return zone
    return name if name.endswith("." + zone) else f"{name}.{zone}"


def data_of(record):
    """The data of a record as one object without empty fields (provider 4.x has a list of one)."""
    data = record.get("data")
    if isinstance(data, list):
        data = data[0] if data else None
    if not isinstance(data, dict):
        return None
    return {k: (str(v).rstrip(".").lower() if k in CASE_INSENSITIVE_FIELDS else str(v))
            for k, v in sorted(data.items()) if v is not None and v != ""} or None


def identity(record, zone):
    """What the DNS record is: zone, name, type and value, in a normal form."""
    rtype = str(record.get("type", "")).upper()
    content = record.get("content")
    data = data_of(record)
    if data is not None and rtype not in SIMPLE_TYPES:
        # Structured records: the data (provider 5.x also computes content from it)
        value = json.dumps(data, sort_keys=True)
    elif rtype in ("A", "AAAA") and isinstance(content, str):
        try:
            value = ipaddress.ip_address(content).compressed
        except ValueError:
            value = content.lower()
    elif rtype in HOSTNAME_TYPES and isinstance(content, str):
        value = content.rstrip(".").lower()
    else:
        value = content
    priority = record.get("priority") if rtype in ("MX", "URI") else None
    return json.dumps([record.get("zone_id"), fqdn(record.get("name"), zone), rtype, value,
                       None if priority is None else float(priority)])


def unknown(value):
    """Whether after_unknown marks a value or any part of it as unknown."""
    if isinstance(value, dict):
        return any(unknown(v) for v in value.values())
    if isinstance(value, list):
        return any(unknown(v) for v in value)
    return value is True


def unknown_identity(after, after_unknown):
    """Whether a part of the identity is known only after apply (content computed from a
    known data, or a priority of a type without one, does not count)."""
    if any(unknown(after_unknown.get(k)) for k in ("zone_id", "name", "type")):
        return True
    rtype = str(after.get("type", "")).upper()
    if rtype in ("MX", "URI") and unknown(after_unknown.get("priority")):
        return True
    if rtype not in SIMPLE_TYPES and (data_of(after) is not None or unknown(after_unknown.get("data"))):
        return unknown(after_unknown.get("data"))
    return unknown(after_unknown.get("content"))


def propose(plan, zone):
    """Returns (moved blocks as (from, to), lines to decide by hand)."""
    deleted, created, manual = {}, {}, []
    for rc in plan.get("resource_changes", []):
        if rc.get("mode") != "managed" or rc.get("type") not in RECORD_TYPES:
            continue
        change = rc.get("change") or {}
        actions = change.get("actions")
        if actions == ["delete"]:
            key = (rc["type"], identity(change.get("before") or {}, zone))
            deleted.setdefault(key, []).append(rc["address"])
        elif actions == ["create"]:
            if unknown_identity(change.get("after") or {}, change.get("after_unknown") or {}):
                manual.append(f"{rc['address']}: created with a value known only after apply")
                continue
            key = (rc["type"], identity(change.get("after") or {}, zone))
            created.setdefault(key, []).append(rc["address"])

    moves = []
    for key in sorted(set(deleted) & set(created)):
        froms, tos = deleted[key], created[key]
        if len(froms) == 1 and len(tos) == 1:
            moves.append((froms[0], tos[0]))
        else:
            manual.append(f"one DNS record, {len(froms)} deleted and {len(tos)} created: pick the pairs by hand")
            manual += [f"  deleted {a}" for a in froms] + [f"  created {a}" for a in tos]
    return moves, manual


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    plan = load_plan(args.plan)
    if not isinstance(plan, dict) or "format_version" not in plan or "planned_values" not in plan:
        print(f"moved-blocks: {args.plan} is not a plan in the JSON format of terraform show -json", file=sys.stderr)
        return 2
    changes = plan.get("resource_changes", [])
    if not isinstance(changes, list) or not all(isinstance(rc, dict) and isinstance(rc.get("address"), str) for rc in changes):
        print(f"moved-blocks: {args.plan}: resource_changes is not a list of changes", file=sys.stderr)
        return 2
    try:
        moves, manual = propose(plan, args.zone)
    except (AttributeError, KeyError, TypeError, ValueError) as e:
        print(f"moved-blocks: {args.plan} has an unexpected structure: {e!r}", file=sys.stderr)
        return 2
    blocks = [f"moved {{\n  from = {a}\n  to   = {b}\n}}\n" for a, b in moves]
    print("\n".join(blocks), end="")
    if manual:
        print("".join(f"# {line}\n" for line in ["Not paired, decide by hand:"] + manual), end="")
        print(f"moved-blocks: {len(moves)} moved blocks; some records need a choice by hand (see the comments)", file=sys.stderr)
        return 1
    print(f"moved-blocks: {len(moves)} moved blocks", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
