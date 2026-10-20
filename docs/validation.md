# Validation

Part of the documentation of [ezdns](../README.md).

The `records` input (and the records of `record_groups`) is validated before any API call. The module checks the structure, the ranges of numeric fields and invariants that hold for every zone; what values mean (which DNSKEY algorithms exist, whether a TLSA certificate matches) is left to the Cloudflare API:

- Record attributes must be known: a misspelled attribute such as `proxid = true` fails with `records["app"]["A"][0]: unknown attribute "proxid"` instead of being ignored, and the same for `settings`

- Supported record types: see [Record Types](record-model.md#record-types), plus `ALIASES` (with an optional prefix, e.g. `"_acme-challenge.TXT"`)
- Records defined by `content` must have a non-empty `content`
- Structured records must have `data` with only the fields of their type and all required ones; other records must not set `data`
- Numeric fields of `data` must be numbers in the range of their DNS wire format: priorities, weights, ports, key tags, `order` and `preference` from 0 to 65535, TLSA, SMIMEA and SSHFP fields and algorithms from 0 to 255, LOC degrees, minutes and seconds within their limits (latitude up to 90, longitude up to 180), LOC `altitude`, `size` and precisions as in RFC 1876, and `lat_direction` `N` or `S`, `long_direction` `E` or `W`; CAA `flags` from 0 to 255
- Service parameters of `HTTPS` and `SVCB` records, see [Record Types](record-model.md#record-types)
- `ttl` and `default_ttl` must be whole numbers: `1` (automatic) or between `minimum_ttl` and `86400`. `minimum_ttl` is `60` by default: Cloudflare accepts TTLs below 60 seconds only on Enterprise zones, where it can be set to `30`; `minimum_ttl = "auto"` takes it from the plan of the zone (`30` on Enterprise, `60` on the others; one more API call, which needs Zone, Zone, Read). A lower TTL, and a `default_ttl` below `minimum_ttl` even if no record uses it, fail at `plan` with what to change; proxied records always get `1`
- Only `A`, `AAAA`, `CNAME` and `ALIASES` records can be `proxied`
- `MX` and `URI` records require `priority`, a whole number from 0 to 65535
- `A` records need an IPv4 address and `AAAA` records an IPv6 address (sent in the canonical form, `2001:db8::1` for `2001:0DB8:0:0:0:0:0:1`, as Cloudflare stores it; the [key](record-model.md#record-keys) keeps the address as written); `CNAME`, `MX`, `NS` and `PTR` records need a DNS name: labels of letters, digits, `_` and `-` (up to 63 characters) separated by dots, at most 253 characters, an optional trailing dot, and not an IP address (`@` stands for the zone apex and is sent as the zone name, and `.` is a null `MX`, RFC 7505, which must have `priority` 0)
- `target` of `SRV`, `HTTPS` and `SVCB` records and `replacement` of `NAPTR` records must be a DNS name by the same rule, or `.` (no service for `SRV`, the owner name for `HTTPS` and `SVCB`, no replacement for `NAPTR`). `@` is not accepted there: the module passes `data` to Cloudflare as written. `URI` targets are URIs and are not checked
- `TXT` values are limited to 2048 characters
- Names, prefixes and `ALIASES` must be valid DNS names: labels of letters, digits, `_` and `-` separated by dots. Internationalized names, also in `zone_name`, must be given in Punycode (`xn--mnchen-3ya` for `münchen`), as the Cloudflare API expects them ([Internationalized Names](recipes.md#internationalized-names) shows how to convert them)
- The fully qualified name of a record (prefix, name and zone together) can have at most 253 characters, and so can the target of a prefixed `ALIASES`
- A wildcard `*` must be the whole leftmost label, also in the names a prefix and a base name combine into (`"_acme-challenge.TXT"` under `"*"` would give `_acme-challenge.*`) and in the targets of `<prefix>.ALIASES`
- A `CNAME` or alias cannot point to its own name (case, a trailing dot, `@` and the short form do not matter)
- `CAA` records require `tag`: `issue`, `issuewild` or `iodef`
- `key` must be a non-empty string without whitespace
- With `require_keys` (record types, e.g. `["A", "AAAA", "TXT"]`), every record of these types must have a `key`. `CNAME` and `ALIASES` cannot be listed: their records are keyed by name, so a new target is an update in place anyway
- Attributes that do not apply to the type of a record (`content` of a record with `data`, `priority` other than on `MX` and `URI`, `tag` and `flags` other than on `CAA`) show a warning, since the module ignores them; they will fail from 3.0
- Two different SPF records on one name, two DMARC records on a `_dmarc` name, and a null `MX` next to other `MX` records on one name (RFC 7505) show a warning: Cloudflare accepts them, but mail receivers do not, see [Troubleshooting](troubleshooting.md#a-name-with-a-null-mx-has-other-mx-records)
- With [`owned_names`](unmanaged-records.md#the-part-of-the-zone-a-module-call-owns), every record must be in the part of the zone that the module call owns
- Record keys must be unique. The error shows where each duplicate is defined, e.g. `"_acme-challenge.app TXT 79bead8e6d65" from records["_acme-challenge.app"]["TXT"][0] and records["app"]["_acme-challenge.TXT"][0]`
- The same record must not be written twice in different forms, which would give it two keys: names in different forms (`www` and `www.example.com`, `@` and the zone name), and values that the [import](importing.md#importing-existing-records) takes for one record (hostnames in any case and with or without a trailing dot, IPv6 addresses in another form, a TXT value quoted or not, numbers in `data` written differently, such as `5060` and `"5060.0"`). Records with a `key` are compared by their keys
- A `CNAME` (including `ALIASES`) cannot share its name with other records, except at the zone apex (`@` or the zone name) where Cloudflare uses CNAME flattening and only `A` and `AAAA` conflict with it, and a name has at most one `CNAME`, also with different `key`s. Names are compared fully qualified, so `www` and `www.example.com` are the same name
- **Migration escape hatch for legacy zones:** existing zones may have names where a `CNAME` shares its name with other records, which Cloudflare accepts for records that are not proxied. Such names can be listed in `allowed_cname_conflicts` (compared fully qualified and case-insensitively), so the zone can be adopted without changing live DNS first. Only the listed names are exempt: a conflict on any other name still fails, a second `CNAME` on a listed name still fails, and a listed name that has no conflict anymore shows a warning so the list can shrink:

  ```hcl
  allowed_cname_conflicts = ["community", "*.legacy"]
  ```

  The listed names must be valid names, written like the names in `records`.

A failed check stops the plan and lists every record that fails it, with where it is defined:

```text
Error: Invalid value for variable

Record data fields and CAA flags must be in range:
records["_sip._tcp"]["SRV"][0].data.port: "70000" (a whole number from 0 to
65535)
```

Attributes that the module ignores only show a warning in 2.x:

```text
Warning: Check block assertion failed

These attributes do not apply to the type of their record and are ignored
(SRV keeps its priority in data; content is for records without data; tag and
flags are for CAA). Remove them: from 3.0 they will fail the plan:
records["app"]["A"][0].priority
```
