#!/usr/bin/env python3
"""Write the records of an existing zone as an ezdns YAML file, to adopt the zone.

The input is a JSON list of DNS records, in one of these forms:

- the response of the Cloudflare API (GET /zones/<zone_id>/dns_records, with
  per_page=5000000 or every page joined), with the records under "result":

      curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \\
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=5000000" > zone.json

- a plain list of such records. The unmanaged_records output of the module
  (report_unmanaged = true) has this form, but without TTL, proxy status, comments and
  tags: records written from it get the defaults, so check them before the import (a
  proxied record written as not proxied would publish its origin address)

    python3 zone-to-ezdns.py zone.json --zone example.com > records.ezdns.yaml

Every value is written as a quoted string, so YAML 1.1 does not turn it into a boolean
or a number. Records that differ only in what is not a part of their key (MX priority,
CAA flags) get a key; with --stable-keys every record but a CNAME gets a key from its
Cloudflare ID (cf-<first 8 characters>), so a later change of its value updates the
record in place instead of deleting and creating it; copies of one record are written once and reported, since the
module cannot import them unambiguously while the zone has several. Then adopt the records with
import_existing = true and import blocks (see docs/importing.md) and check that the
plan creates and deletes nothing.

Python 3.8 or later, standard library only. Exit status: 0, or 1 when records were
skipped or are copies of each other (the YAML is written anyway), 2 for bad input.
"""

import argparse
import hashlib
import json
import pathlib
import re
import sys

# Fields of the structured records, as the module takes them in data (other fields that
# the API returns, such as name, proto and service of SRV records, are left out)
DATA_FIELDS = {
    "SRV": ["priority", "weight", "port", "target"],
    "URI": ["weight", "target"],
    "HTTPS": ["priority", "target", "value"],
    "SVCB": ["priority", "target", "value"],
    "TLSA": ["usage", "selector", "matching_type", "certificate"],
    "SMIMEA": ["usage", "selector", "matching_type", "certificate"],
    "SSHFP": ["algorithm", "type", "fingerprint"],
    "DS": ["key_tag", "algorithm", "digest_type", "digest"],
    "DNSKEY": ["flags", "protocol", "algorithm", "public_key"],
    "CERT": ["type", "key_tag", "algorithm", "certificate"],
    "NAPTR": ["order", "preference", "flags", "service", "regex", "replacement"],
    "LOC": [
        "lat_degrees", "lat_minutes", "lat_seconds", "lat_direction",
        "long_degrees", "long_minutes", "long_seconds", "long_direction",
        "altitude", "size", "precision_horz", "precision_vert",
    ],
}
# The JSON Schema of a release, linked at the top of the YAML for completion in editors
SCHEMA_URL = "https://raw.githubusercontent.com/5xxeu/terraform-cloudflare-ezdns/{ref}/schema/records.schema.json"
CONTENT_TYPES = ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY"]
PROXIABLE = ["A", "AAAA", "CNAME"]


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Write the records of an existing zone as an ezdns YAML file.")
    parser.add_argument("input", help="JSON records (Cloudflare API response or unmanaged_records), or - for standard input")
    parser.add_argument("--zone", required=True, metavar="NAME", help="zone name, e.g. example.com")
    parser.add_argument("--default-ttl", type=int, default=3600, metavar="SECONDS",
                        help="default_ttl of the module call: records with this TTL are written without one (default 3600)")
    parser.add_argument("--stable-keys", action="store_true",
                        help="give every record but a CNAME a key from its Cloudflare ID (cf-<first 8 characters>), so "
                             "changing its value later updates it in place")
    parser.add_argument("--schema", metavar="URL_OR_PATH",
                        help="JSON Schema linked at the top of the YAML: a URL, or a path relative to the YAML file such as "
                             "modules/ezdns/schema/records.schema.json (default: the schema of the module release this script "
                             "comes with, on GitHub)")
    args = parser.parse_args(argv)
    # The link goes into a YAML comment: a line break would end it (YAML also breaks
    # lines at NEL and the Unicode line and paragraph separators, see quote())
    if args.schema is not None and (args.schema == "" or re.search("[\x00-\x1f\x7f-\x9f\u2028\u2029\ufeff]", args.schema)):
        parser.error("--schema must be a URL or a path on one line")
    return args


def default_schema():
    """The schema URL of the module release this script is in: its version is the first
    version heading of CHANGELOG.md next to tools/. main when the copy has no CHANGELOG."""
    try:
        changelog = (pathlib.Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text(encoding="utf-8")
    except OSError:
        changelog = ""
    version = re.search(r"^## \[(\d+\.\d+\.\d+)\]", changelog, re.M)
    return SCHEMA_URL.format(ref=f"v{version.group(1)}" if version else "main")


def load(path):
    try:
        if path == "-":
            data = json.load(sys.stdin)
        else:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
    except (OSError, ValueError) as e:
        print(f"zone-to-ezdns: cannot read {path}: {e}", file=sys.stderr)
        raise SystemExit(2) from None
    if isinstance(data, dict) and isinstance(data.get("result"), list):
        # One page of a longer list would give the configuration of part of the zone
        info = data.get("result_info")
        total = info.get("total_count") if isinstance(info, dict) else None
        pages = info.get("total_pages") if isinstance(info, dict) else None
        if isinstance(total, int) and len(data["result"]) < total:
            print(f"zone-to-ezdns: {path} has {len(data['result'])} of {total} records (one page of the "
                  f"response): use per_page=5000000 or join every page", file=sys.stderr)
            raise SystemExit(2)
        # Without total_count, a response of several pages holds one of them
        if not isinstance(total, int) and isinstance(pages, int) and pages > 1:
            print(f"zone-to-ezdns: {path} is one of {pages} pages of the response: use per_page=5000000 "
                  f"or join every page", file=sys.stderr)
            raise SystemExit(2)
        data = data["result"]
    if not isinstance(data, list) or not all(isinstance(r, dict) for r in data):
        print(f"zone-to-ezdns: {path} is not a list of records (nor an API response with result)", file=sys.stderr)
        raise SystemExit(2)
    return data


def relative(name, zone):
    name = (name or "").rstrip(".").lower()
    zone = zone.rstrip(".").lower()
    if name == zone:
        return "@"
    if name.endswith("." + zone):
        return name[: -len(zone) - 1]
    return None


def text(value):
    """A value of data as text, the way the module keeps it (numbers without a fraction
    as whole numbers)."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def convert(records, zone, default_ttl, stable_keys=False):
    """Returns ({name: {type: [record, ...]}}, notes); notes lists what needs attention."""
    out, notes = {}, []
    for r in records:
        rtype = str(r.get("type", "")).upper()
        name = relative(r.get("name"), zone)
        label = f"{rtype} {r.get('name')} ({r.get('id', 'no ID')})"
        if name is None:
            notes.append(f"skipped {label}: not in the zone {zone}")
            continue
        if (r.get("meta") or {}).get("read_only") or r.get("read_only"):
            notes.append(f"skipped {label}: read only, managed by Cloudflare")
            continue
        if rtype not in CONTENT_TYPES and rtype not in DATA_FIELDS and rtype != "CAA":
            notes.append(f"skipped {label}: the module does not support {rtype} records")
            continue

        rec = {}
        data = r.get("data") or {}
        if rtype == "CAA":
            rec["content"] = text(data.get("value", ""))
            rec["tag"] = text(data.get("tag", ""))
            flags = int(float(data.get("flags", 0) or 0))
            if flags:
                rec["flags"] = flags
        elif rtype in DATA_FIELDS:
            rec["data"] = {f: text(data[f]) for f in DATA_FIELDS[rtype] if data.get(f) is not None}
        else:
            rec["content"] = text(r.get("content", ""))
        if rtype in ("MX", "URI") and r.get("priority") is not None:
            rec["priority"] = int(float(r["priority"]))
        # Written both ways, so default_proxied or the defaults of a group do not change
        # a record of the zone
        if rtype in PROXIABLE and isinstance(r.get("proxied"), bool):
            rec["proxied"] = r["proxied"]
        if rtype in PROXIABLE and "proxied" not in r:
            notes.append(f"{label}: the input does not say whether it is proxied, written as not proxied: check it")
        ttl = r.get("ttl")
        if ttl is not None and not rec.get("proxied") and int(ttl) != default_ttl:
            rec["ttl"] = int(ttl)
        if r.get("comment"):
            rec["comment"] = r["comment"]
        if r.get("tags"):
            rec["tags"] = list(r["tags"])
        settings = {k: True for k in ("flatten_cname", "ipv4_only", "ipv6_only") if (r.get("settings") or {}).get(k) is True}
        if settings:
            rec["settings"] = settings
        if r.get("private_routing") is True:
            rec["private_routing"] = True
        rec["_id"] = r.get("id", "no ID")
        out.setdefault(name, {}).setdefault(rtype, []).append(rec)

    for name, types in out.items():
        for rtype, recs in types.items():
            # Copies of one record (also with another TTL, comment or tags): written once
            # (the module rejects a record listed twice), and the import of it stops until
            # the zone has one. Reported by ID, not by value: the value of a proxied
            # record is the origin address
            copies = {}
            for rec in recs:
                copies.setdefault(json.dumps(identity(rtype, rec), sort_keys=True), []).append(rec)
            for same in copies.values():
                # Copies that differ in the proxy are not written once: deleting the proxied
                # one would publish the origin, so the choice is left to a person
                if len(same) > 1 and len({r.get("proxied") for r in same}) > 1:
                    ids = ", ".join(str(r["_id"]) for r in same)
                    notes.append(f"{len(same)} {rtype} records of {name} in the zone (IDs {ids}) differ only in proxied: all are written, choose by hand which one to keep (deleting the proxied one publishes its address)")
                    continue
                if len(same) > 1:
                    for rec in same[1:]:
                        recs.remove(rec)
                    ids = ", ".join(str(r["_id"]) for r in same)
                    notes.append(f"{len(same)} copies of one {rtype} record of {name} in the zone (IDs {ids}), written once: delete the other copies in the zone before the import")

            # Keys from the Cloudflare ID: a CNAME has no value in its key and one per
            # name, so it keeps the key of the module
            if stable_keys and rtype != "CNAME":
                for rec in recs:
                    if re.fullmatch(r"[0-9A-Za-z]+", str(rec["_id"])):
                        rec["key"] = f"cf-{str(rec['_id'])[:8].lower()}"
                    else:
                        notes.append(f"{rtype} record of {name} has no Cloudflare ID: written without a stable key")

            # Records that the module would give the same key: MX and URI records that
            # differ only in priority and CAA records that differ only in flags get a key
            # each (records with a stable key have one already)
            groups = {}
            for rec in recs:
                if "key" not in rec:
                    groups.setdefault(module_key(rtype, rec), []).append(rec)
            keyed = []
            for key, same in groups.items():
                if len(same) > 1 and rtype in ("MX", "URI", "CAA"):
                    for rec in same:
                        rec["key"] = f"priority-{rec.get('priority', 0)}" if rtype != "CAA" else f"flags-{rec.get('flags', 0)}"
                    keyed.append((key, same))
            # Keys are unique within the name and type: two MX targets with the same pair
            # of priorities both get priority-10, so the value goes into the key then
            used = [r.get("key") or module_key(rtype, r) for r in recs]
            for key, same in keyed:
                if any(used.count(r["key"]) > 1 for r in same):
                    first = same[0]
                    value = first.get("content") or (first.get("data") or {}).get("target") or key
                    value = re.sub(r"\s+", "-", f"{first['tag']} {value}" if rtype == "CAA" else value)
                    for rec in same:
                        rec["key"] = f"{value}-{rec['key']}"
            used = [r.get("key") or module_key(rtype, r) for r in recs]
            for rec in recs:
                if used.count(rec.get("key") or module_key(rtype, rec)) > 1:
                    notes.append(f"{rtype} record {rec['_id']} of {name} gets the same key as another record: give them keys by hand")
            for rec in recs:
                del rec["_id"]
    return out, notes


def identity(rtype, rec):
    """The fields that make a DNS record (not its TTL, comment, tags or proxy)."""
    return {k: rec[k] for k in ("content", "priority", "tag", "flags", "data") if k in rec}


def module_key(rtype, rec):
    """The value part of the record key of the module, to find records that collide."""
    if rtype == "CNAME":
        return "CNAME"
    if rtype == "CAA":
        return f"{rec['tag']} {rec['content']}"
    if rtype == "TXT":
        return hashlib.sha1(rec["content"].encode()).hexdigest()[:12]
    if "data" in rec:
        return json.dumps(rec["data"], sort_keys=True)
    return rec["content"]


def quote(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    # JSON escapes the C0 controls; YAML also reads NEL and the Unicode line and
    # paragraph separators as line breaks and rejects DEL, the C1 controls and the
    # BOM, so these are escaped too. Other non-ASCII text stays readable
    return re.sub("[\x7f-\x9f\u2028\u2029\ufeff\ufffe\uffff]", lambda m: f"\\u{ord(m.group()):04x}",
                  json.dumps(value, ensure_ascii=False))


def to_yaml(records, zone, count, schema=None):
    order = ["content", "key", "priority", "tag", "flags", "data", "ttl", "proxied", "comment", "tags", "settings", "private_routing"]
    lines = [
        f"# yaml-language-server: $schema={schema or default_schema()}",
        f"# Records of {zone} written by zone-to-ezdns.py ({count} records). Review them, then adopt them with",
        "# import_existing = true and import blocks, and check that the plan creates and deletes nothing.",
        # An empty zone: records: without a value decodes to null, which the module rejects
        "records:" if records else "records: {}",
    ]
    for name in sorted(records, key=lambda n: (n != "@", n.split(".")[::-1])):
        lines.append(f"  {quote(name)}:")
        for rtype in sorted(records[name]):
            lines.append(f"    {rtype}:")
            for rec in records[name][rtype]:
                first = True
                for field in order:
                    if field not in rec:
                        continue
                    prefix = "      - " if first else "        "
                    first = False
                    value = rec[field]
                    if isinstance(value, dict):
                        lines.append(f"{prefix}{field}:")
                        lines += [f"          {k}: {quote(v)}" for k, v in value.items()]
                    elif isinstance(value, list):
                        lines.append(f"{prefix}{field}: [{', '.join(quote(v) for v in value)}]")
                    else:
                        lines.append(f"{prefix}{field}: {quote(value)}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    raw = load(args.input)
    # A record of an unexpected shape (a name that is not text, data that is not an
    # object) is a broken input: nothing is written and the exit status is 2
    try:
        records, notes = convert(raw, args.zone, args.default_ttl, args.stable_keys)
        count = sum(len(recs) for types in records.values() for recs in types.values())
        out = to_yaml(records, args.zone.rstrip("."), count, args.schema)
    except (AttributeError, KeyError, TypeError, ValueError) as e:
        print(f"zone-to-ezdns: {args.input} has a record of an unexpected shape: {e!r}", file=sys.stderr)
        return 2
    sys.stdout.write(out)
    for note in notes:
        print(f"zone-to-ezdns: {note}", file=sys.stderr)
    return 1 if notes else 0


if __name__ == "__main__":
    sys.exit(main())
