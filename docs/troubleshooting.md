# Troubleshooting

Part of the documentation of [ezdns](../README.md).

The errors and warnings that come up most often, with the beginning of their text as Terraform prints it, why they happen and what to do. Every error of the module names the records it is about and where they are defined (`records["app"]["A"][0]`, `record_groups["mail"].records[...]`).

- [Errors at plan](#errors-at-plan)
- [Errors at apply](#errors-at-apply)
- [Warnings](#warnings)
- [Unexpected plans](#unexpected-plans)

## Errors at Plan

### The "for_each" value depends on resource attributes that cannot be determined until apply

A record takes its value from another resource (`content = aws_instance.web.public_ip`), which is known only after apply, and the value is a part of the record key. Give the record a `key`, which takes the place of the value in the address:

```hcl
"web" = {
  A = [
    { content = aws_instance.web.public_ip, key = "web" },
  ]
}
```

Values of other attributes (`ttl`, `comment`) known only after apply need no key. See [Record Keys](../README.md#record-keys).

### Duplicate records (remove the duplicates or set a unique key for each of them; ...

Two records get the same key, or are the same DNS record written in two forms. The message lists each pair with where both are defined. Common causes:

- The same value twice in one list, or in `records` and in a group of `record_groups`.
- MX records with the same host and different priorities, or CAA records that differ only in flags: neither priority nor flags are a part of the key, so give each record a `key` (`key = "primary"`, `key = "backup"`).
- One name written in two forms (`www` and `www.example.com`, `@` and the zone name): remove one of them.
- An `ALIASES` entry and a `CNAME` record for the same name.

### A CNAME record cannot share its name with other records (except at the zone apex), and a name has at most one CNAME.

DNS does not allow a CNAME next to other records of the same name, and Cloudflare rejects it. Remember that `ALIASES` entries are CNAME records too. Put the other records on the target of the CNAME, or replace the CNAME with the records it points to. A zone that already has such names (Cloudflare accepted them for records that are not proxied) can list them in `allowed_cname_conflicts` while they are cleaned up.

### Invalid records (allowed attributes: content, ttl, proxied, priority, tag, flags, data, key, comment, tags, settings, private_routing):

A record has an attribute the module does not know, usually a typo (`proxid`, `prority`), or is not an object. Terraform would drop an unknown attribute without a word, so the module stops instead. Fix the attribute named after `unknown attribute`.

### TTLs below 60 seconds are only available on the Cloudflare Enterprise plan.

A record or `default_ttl` has a TTL below 60 seconds (other than `1`, automatic). Use at least 60, or `1`; on an Enterprise zone, set `minimum_ttl = 30` (or `"auto"`, to take it from the plan of the zone).

### These records are outside owned_names (included: ...; excluded: ...), the part of the zone that this module call manages:

The module call has `owned_names`, and a record is on a name outside it: often a typo in the name, or a record that belongs to another module call. Fix the name, move the record, or widen `owned_names`. See [The Part of the Zone a Module Call Owns](unmanaged-records.md#the-part-of-the-zone-a-module-call-owns).

### zone_name must be in Punycode / The zone "münchen.de" has an internationalized name

Cloudflare returns the names of internationalized zones in Unicode, which cannot be used for the fully qualified names of records. Set `zone_name` in Punycode (`xn--mnchen-3ya.de`), or use the `idna` submodule, which converts names. See [Internationalized Names](recipes.md#internationalized-names).

### These records cannot be imported unambiguously: each matches several existing records, ...

With `import_existing = true`, a configured record matches several records of the zone (copies of one record), or two configured records match the same existing one. Remove the copies from the zone, or give the records distinct values. To import one anyway, set `import_existing = false` and write an `import` block for it. See [Importing Existing Records](importing.md#importing-existing-records).

### The lookup of existing ... records returned ... records (the limit)

The zone has more records of one type than the lookup returns at once (100,000), so `import_existing` and `report_unmanaged` cannot see all of them. Split the zone, or import the records with `import` blocks and leave both options off.

### A record with ignore_changes is found in the zone by its name and type ...

A record with [`ignore_changes`](../README.md#values-changed-outside-terraform) takes its values from the record of the same name and type in the zone, and the module cannot tell which one it is: the zone has several records of that name and type that no other configured record describes by value, or the configuration has two records with `ignore_changes` on one name and type. Delete the extra records in the zone, describe them in `records`, or keep one record with `ignore_changes` per name and type.

### ignore_changes needs provider v5

The v4 wrapper has no lookup of the records of a zone, which `ignore_changes` reads. Move to provider v5 (see [Upgrading](upgrading.md#from-provider-v4-to-v5)), or remove `ignore_changes`.

## Errors at Apply

### Record already exists / An identical record already exists

The record is in the zone already, created outside this configuration (in the dashboard, by another tool or another module call). Adopt it into the state instead of creating it: `import_existing = true` and an `import` block, see [Importing Existing Records](importing.md#importing-existing-records). For a whole zone, `tools/zone-to-ezdns.py` writes the configuration of the existing records first.

### An A, AAAA, or CNAME record with that host already exists

A record of the configuration conflicts with a record in the zone that the configuration does not describe (a CNAME on a name that has other records, or the other way round). The module checks conflicts between configured records at `plan`, but cannot see records it does not manage unless `report_unmanaged = true` lists them. Remove or adopt the record in the zone.

## Warnings

### These attributes do not apply to the type of their record and are ignored

A record sets an attribute its type does not use: `priority` on an A record, `content` on a record with `data`, `tag` outside CAA, or `priority` on SRV (it belongs in `data`). The attribute has no effect; remove it. From 3.0 this will be an error.

### Text values given as numbers are written in their canonical form

A text value was given as a number, usually in YAML without quotes (`content: 0123`), and Terraform writes the number (`123`). Quote the value to keep it as written.

### The zone has ... records that the configuration does not describe

`report_unmanaged = true` found records in the zone that are not in the configuration. Add them to `records`, leave expected ones out with `unmanaged_ignore` (the TXT ownership records of external-dns, ACME challenges), or limit the call to its part of the zone with `owned_names`. The module never deletes them. See [Records Not in the Configuration](unmanaged-records.md#records-not-in-the-configuration).

## Unexpected Plans

### The plan deletes and creates a record whose value I changed

A record without a `key` is addressed by its value, so a new value is a new record: Terraform deletes the old one and creates the new one, with a short gap between them. Give records whose values change a `key`, then the change is an update in place. See [Changing Values Without a Gap](../README.md#changing-values-without-a-gap).

### The plan deletes and creates a record whose name I only rewrote

`www`, `WWW` and `www.example.com` are one DNS name, but the key keeps the name as written, so rewriting it gives the record a new address. Do not apply such a plan: the delete and the create run in no fixed order, so the name either stops answering for a moment or the create fails as a copy of the record that still exists. Add a `moved` block from the old key to the new one, see [Record Keys](../README.md#record-keys); the plan then changes nothing.

A rename to another name (`app` to `api`) is a delete and a create too, and the old name stops answering at once, as it should. A `moved` block keeps the Cloudflare record (its ID and comment) and changes its name; to keep both names answering for a while, add the new name in one apply and remove the old one in the next.

### The plan creates records that exist in the zone

The records were created outside this configuration. Without `import_existing`, the apply fails with "record already exists"; see [Record already exists](#record-already-exists--an-identical-record-already-exists).

### The plan replaces every record after an upgrade

Within 2.x the record keys do not change. Check the [upgrade notes](upgrading.md#upgrading-and-migration) of the versions in between, and that the `source` (Registry, local copy, Git) and the module address in the state are the same as before ([From an Earlier Address](upgrading.md#from-an-earlier-address)).
