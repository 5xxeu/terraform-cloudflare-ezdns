# Record Model

Part of the documentation of [ezdns](../README.md).

The module flattens the input map into a single map with a unique key for each record, which is then used in `for_each`.

## Record Types and Nested Names
Each key inside a base name block is a record type (`A`, `AAAA`, `CNAME`, `TXT`, `MX`, `CAA`, `SRV`, ...; see [Record Types](#record-types)). A key with a dot-notation (like `"_acme-challenge.TXT"`) is split: the last part is the record type, everything before it is prepended to the base name. Inside the `@` block the prefix becomes the record name itself (`"_dmarc.TXT"` becomes `_dmarc.example.com`).

## Record Types

Most records are defined by `content`. Structured records are defined by a `data` map instead, with the same fields as in the Cloudflare API. The module only checks which fields are present; what the fields and their values mean is described in the Cloudflare [DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/) and in the `data` attribute of [`cloudflare_dns_record`](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record), as are `settings`:

| Type | Defined by | `data` fields (optional in italics) |
|------|-----------|--------------------------------------|
| `A`, `AAAA`, `CNAME`, `NS`, `PTR`, `TXT` | `content` | - |
| `MX` | `content`, `priority` | - |
| `OPENPGPKEY` | `content` | - (provider v5 only) |
| `CAA` | `content`, `tag`, `flags` | - |
| `SRV` | `data` | `priority`, `weight`, `port`, `target` |
| `URI` | `data`, `priority` | `weight`, `target` |
| `HTTPS`, `SVCB` | `data` | `priority`, `target`, *`value`*, or service parameters instead of `value`: *`mandatory`*, *`alpn`*, *`port`*, *`ipv4hint`*, *`ech`*, *`ipv6hint`* |
| `TLSA`, `SMIMEA` | `data` | `usage`, `selector`, `matching_type`, `certificate` |
| `SSHFP` | `data` | `algorithm`, `type`, `fingerprint` |
| `DS` | `data` | `key_tag`, `algorithm`, `digest_type`, `digest` |
| `DNSKEY` | `data` | `flags`, `protocol`, `algorithm`, `public_key` |
| `CERT` | `data` | `type`, `key_tag`, `algorithm`, `certificate` |
| `NAPTR` | `data` | `order`, `preference`, `replacement`, *`flags`*, *`service`*, *`regex`* |
| `LOC` | `data` | `lat_degrees`, `lat_minutes`, `lat_seconds`, `lat_direction`, `long_degrees`, `long_minutes`, `long_seconds`, `long_direction`, *`altitude`*, *`size`*, *`precision_horz`*, *`precision_vert`* |

Service parameters of `HTTPS` and `SVCB` records (RFC 9460) can be written as text in `value` (`alpn="h3,h2" port="443"`) or as fields of `data`, which the module writes into `value` in the order of their keys, each in quotes: lists such as `alpn`, `mandatory`, `ipv4hint` and `ipv6hint` are comma-separated, `ech` is base64. A record uses one form or the other, not both. The fields are checked at `plan` (addresses in the hints, protocol IDs without spaces, `port` from 0 to 65535). The record key is the hash of `data` as written, so switching an existing record from `value` to fields gives it a new key: set a `key` first, or move it with a `moved` block.

```hcl
"@" = {
  HTTPS = [{
    key  = "web"
    data = { priority = 1, target = ".", alpn = "h3,h2", ipv4hint = "192.0.2.1" }
    # value = alpn="h3,h2" ipv4hint="192.0.2.1"
  }]
}
```

The service and protocol of `SRV`, `URI` and `TLSA` records are part of the name:

```hcl
"_sip._tcp" = {
  SRV = [{
    data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
  }]
}
"mail" = {
  "_25._tcp.TLSA" = [{
    key  = "mx"
    data = { usage = 3, selector = 1, matching_type = 1, certificate = "..." }
  }]
}
```

## The `ALIASES` Logic
When you define `ALIASES` inside a block (e.g., inside `"app"`), the module creates a `CNAME` record for each entry where:
- **Name**: The value provided in `content` (e.g., `support` for support.example.com).
- **Target**: The base name plus the zone domain (e.g., `app.example.com`, or `example.com` for `@`).

A base name may be short (`app`) or fully qualified (`app.example.com`): the target is the same fully qualified name, and `@` or the zone name point to the zone apex.

## Inline Aliases
A key like `"cdn.ALIASES"` works the same way, but the target is the prefixed name: `cdn.app.example.com` (or `cdn.example.com` for `@`).

## Record Keys
Each record is keyed in the state by its content, in the zone file format `<name> <TYPE> <value>`, so adding, removing or reordering items in a list affects only those items:

| Record | Key |
|--------|-----|
| `A`, `AAAA`, `MX`, `NS`, `PTR` | `app A 192.0.2.10`, `@ MX mail.example.com` |
| `TXT` | `_dmarc TXT 21541c4e7044` (first 12 characters of the SHA-1 of the value) |
| Records with `data` (`SRV`, `TLSA`, ...) | `_sip._tcp SRV 9c61601f99e8` (first 12 characters of the SHA-1 of the data) |
| `CNAME` and `ALIASES` | `www CNAME` (only one CNAME is allowed per name) |
| `CAA` | `app CAA issue letsencrypt.org` |
| Any record with `key` | `google._domainkey TXT dkim` |

```
module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"]
```

With the `v5` submodule the address is `module.dns.cloudflare_dns_record.record[...]`, with the `v4` submodule `module.dns.cloudflare_record.record[...]`.

Since the value is a part of the key, changing it replaces the record. For values that change over time (e.g. DKIM rotation or a server IP), set an explicit `key`, so the record is updated in place:

```hcl
"google._domainkey.TXT" = [
  { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
]
```

### When to Use `key`

Use a `key` whenever the value of a record is expected to change, or is not known until `apply`:

- DKIM keys and other rotated values
- ACME challenge tokens and service verification records
- server IPs that change, e.g. after a migration
- values from other resources (`content = aws_instance.web.public_ip`)
- `MX` records that differ only in priority, `CAA` records that differ only in flags

Without a `key`, a changed value is a new record: the old one is deleted and the new one created. To make sure no such record is missed, list the types that need a `key` in `require_keys`: a record of these types without a `key` fails at `plan`, with where it is defined:

```hcl
require_keys = ["A", "AAAA", "TXT"]
```

**Values computed by other resources need a `key`.** `for_each` keys must be known at `plan`, so a record whose value comes from another resource (`content = aws_instance.web.public_ip`) fails with "The "for_each" value depends on resource attributes that cannot be determined until apply" unless it has a `key`:

```hcl
"web" = {
  A = [
    { content = aws_instance.web.public_ip, key = "web" }, # record key "web A web"
  ]
}
```

Two records that produce the same key (e.g. the same value listed twice, or a `CNAME` and an alias with the same name) fail at `plan` with the list of duplicates and where each of them is defined. `MX` records that differ only in `priority` and `CAA` records that differ only in `flags` get the same key too, since neither is a part of it; give each of them a `key`:

```hcl
MX = [
  { content = "mx.example.net", priority = 10, key = "primary" },
  { content = "mx.example.net", priority = 20, key = "backup" },
]
```

A `key` does not make a copy of a record a new one: two records with the same name, type and value (and priority, for `MX` and `URI`) fail at `plan` whatever their keys, since Cloudflare rejects identical records at `apply`.

Names are sent to Cloudflare in lower case, as Cloudflare stores them; the key keeps the name as written (`M1._domainkey TXT dkim`).

**Rewriting a name in another form changes its key.** `www`, `WWW` and `www.example.com` are the same DNS name, but the key keeps the form as written, so changing it (`www` to `www.example.com`, or `WWW` to `www`) gives the record a new address, and Terraform plans to delete and create it. The two are different instances, so their order is not fixed: when the delete goes first, the name does not answer until the create, and resolvers cache the empty answer for the negative TTL of the zone; when the create goes first, Cloudflare may reject it as a copy of the record that still exists, and the apply fails. To keep the existing record, add a `moved` block with the old and the new key, then check that the plan neither deletes nor creates it:

```hcl
moved {
  from = module.dns.module.v5.cloudflare_dns_record.record["www A 192.0.2.10"]
  to   = module.dns.module.v5.cloudflare_dns_record.record["www.example.com A 192.0.2.10"]
}
```

With the `//modules/dns/v5` submodule, the address has no `module.v5`; with the v4 wrapper, the resource is `cloudflare_record.record`.

`tools/moved-blocks.py` writes these blocks from a saved plan: it pairs each record that the plan deletes with the created record that is the same DNS record (zone, fully qualified name, type and value; TTL, proxy status, comment and tags change in place after the move). Copies of one record and values known only after apply are listed as comments to pair by hand (exit status 1):

```console
$ terraform plan -out=tfplan && terraform show -json tfplan > tfplan.json
$ python3 tools/moved-blocks.py tfplan.json --zone example.com > moved.tf
```

Check the blocks, apply, and remove them once every state that uses the module is applied.

## Changing Values Without a Gap

A changed value without a `key` gives the record a new key, so Terraform deletes the old record and creates the new one. Between the two, resolvers can get an empty answer and cache it for the negative TTL of the zone (the minimum of its SOA record). `create_before_destroy` does not change this: the old and the new record are different instances, and the option only orders the replacement of one instance. Two ways avoid the gap:

- **Update in place.** Give the record a `key` (see [When to Use `key`](#when-to-use-key)): the value changes on the same record, which answers with the old or the new value, never with none. The plan shows the difference:

  ```text
  # without a key: two resources, a gap between them
    # module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"] will be destroyed
    # module.dns.module.v5.cloudflare_dns_record.record["app A 198.51.100.10"] will be created

  # with key = "web": one resource, changed in place
    # module.dns.module.v5.cloudflare_dns_record.record["app A web"] will be updated in place
  ```
- **Overlap in steps**, when old and new values should both answer for a while, or when the record type changes. For a server move:

  1. Lower the TTL of the record (e.g. to 300) and apply. Wait for the old TTL to expire, so that resolvers have the short one.
  2. Add the new address next to the old one, each with a `key` (`old`, `new`), and apply. Clients now get both addresses.
  3. Check the new server, then remove the `old` record and apply.
  4. Restore the TTL.

  ```hcl
  "app" = {
    A = [
      { key = "old", content = "192.0.2.10", ttl = 300 },
      { key = "new", content = "198.51.100.10", ttl = 300 },
    ]
  }
  ```

  DKIM keys rotate the same way with a second selector: publish `s2._domainkey` next to `s1._domainkey`, switch the sender to `s2`, and remove `s1` after the messages signed with it have been delivered.

The same holds for proxied records: Cloudflare answers for them with its own addresses, but only while the record exists, so a changed origin address needs a `key` too. A type change on one name (an `A` record to a `CNAME`) cannot overlap: a CNAME cannot share its name with other records, so it is a delete and a create, in two applies or in one. A [check of the saved plan](plan-guard.md#checking-plans-before-apply) shows every replacement and deletion before it is applied.

## Values Changed Outside Terraform

A record whose value something else changes (a DDNS client that updates an address, a client that writes a token into an existing record, a proxy switched off in the dashboard during an incident) would be changed back by every apply. `ignore_changes` on the record lists the attributes that come from the record in the zone instead of the configuration, so a change made outside Terraform plans no change (provider v5):

```hcl
records = {
  "home" = {
    A = [{ key = "ddns", content = "192.0.2.1", ttl = 60, ignore_changes = ["content"] }]
  }
  "_acme-challenge" = {
    TXT = [{ key = "token", content = "pending", ignore_changes = ["content"] }]
  }
}
```

A client that creates and deletes records of its own (cert-manager and most ACME clients create a challenge record and delete it afterwards) needs no `ignore_changes`: leave its records out of `records`, and out of the report with [`unmanaged_ignore`](examples.md#next-to-external-dns-and-cert-manager). `ignore_changes` is for a record that the module creates and something else updates.

The attributes are `content` (with `data` for structured records), `ttl`, `proxied`, `comment` and `tags`. The module still creates and deletes the record, and the attributes not listed stay managed. Terraform allows only literal values in `lifecycle`, so this is not `lifecycle { ignore_changes }`: the module reads the record from the zone at every `plan` (one lookup by name per such record, or within the lookup of its type that `import_existing` or `report_unmanaged` make anyway; DNS Read is enough) and sends the values it finds, so the plan has nothing to change. How it works out:

- **The record in the zone is found by name and type.** Cloudflare does not know the record key, and the configuration cannot read the ID in the state. So that it stays the same record whatever else changes, a record with `ignore_changes` is the only configured record of its type on its name (other `TXT` records go on another name, an `MX` with `ignore_changes` is the only `MX` of its name), and the zone may have at most one record of that name and type: otherwise the plan stops and lists them. A changed priority of an `MX` or `URI` record keeps the record.
- **A record not in the zone yet is created with the configured values**, and so is a record deleted outside Terraform: the configured value is the starting value.
- **A record that already exists** (created by the DDNS client before the module call) is adopted with `import_existing`, whatever its value, and [`report_unmanaged`](unmanaged-records.md#records-not-in-the-configuration) does not list it.
- **Changing a listed attribute in the configuration has no effect** while the record exists. Remove it from `ignore_changes` to set it: the next plan writes the configured value.
- **Use a `key`**, as in the example: without one, the record key has the configured value, which is no longer the value of the record.
- **A zone created in the same apply** has no records to read at `plan`, so the values are known only after apply, as with `import_existing`.
- **Provider v4** has no lookup of the records of a zone: the v4 wrapper stops the plan for a record with `ignore_changes`. The [`compile` submodule](testing.md#testing-your-records), which reads nothing, returns the configured values.
