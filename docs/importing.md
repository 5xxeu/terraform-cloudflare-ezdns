# Importing Existing Records

Part of the documentation of [ezdns](../README.md).

When the zone already has records, the first `apply` would fail with "record already exists" for each of them. With provider v5 (the root module or the `v5` submodule), the module can find the existing records and adopt them into the state instead. It works the same with records in HCL or in YAML; see [`examples/import`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/examples/import).

> **`import_existing` does not import anything by itself.** It only finds the IDs of existing records and exposes them in `import_ids`; the `import` block in step 2 does the import. It is not a reconciliation either: records of the zone that are not in `records` are left alone.

Each lookup reads up to 100,000 records of one type (10,000 before 2.13.0), a limit of the module; in a zone with more records of a configured type, the rest are not found and would be created again. When a lookup returns 100,000 records, `plan` stops: set `import_existing = false` and import the records with `import` blocks of their own.

1. Set `import_existing = true`. The module then reads the records of the zone (the API token needs the `DNS Read` permission) and matches them to the configured records by name, type and value. The records are read with one request per record type of the configuration, which avoids a provider crash on zones with CAA records ([cloudflare/terraform-provider-cloudflare#7004](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004)).
2. Add an `import` block next to the module call:

   ```hcl
   import {
     for_each = module.dns.import_ids
     to       = module.dns.module.v5.cloudflare_dns_record.record[each.key]
     id       = each.value
   }
   ```

   With the `//modules/dns/v5` submodule, the address has no `module.v5`: `module.dns.cloudflare_dns_record.record[each.key]`.

3. Run `terraform plan`. Existing records are shown as imported, and only records missing in the zone are created. Check that no record you expect to be imported is shown as created:

   ```text
     # module.dns.module.v5.cloudflare_dns_record.record["@ MX mx.example.net"] will be imported
     # module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"] will be imported
     # module.dns.module.v5.cloudflare_dns_record.record["new A 192.0.2.20"] will be created

   Plan: 2 to import, 1 to add, 0 to change, 0 to destroy.
   ```
4. Run `terraform apply`, then remove the `import` block and `import_existing`, so the zone is not read on every plan.

For structured records (`SRV`, `HTTPS`, `TLSA`, ...), provider v5 plans a one-time in-place update right after the import, without visible changes; after the `apply`, the plan is empty.

Matching ignores the case and a trailing dot of names, hostnames (`target`, `replacement`, the issuer domain of CAA `issue`/`issuewild` values) and hex values (`digest`, `fingerprint`, and `certificate` of TLSA and SMIMEA records); other `data` fields (also the `target` of URI records, whose paths are case-sensitive), CAA parameters after `;`, `iodef` URLs and OPENPGPKEY keys must match exactly. IPv6 addresses are compared in their canonical form (`2001:0db8:0:0:0:0:0:1` is `2001:db8::1`), numeric `data` fields as numbers (`port = "5060.0"` is `5060`), and `@` as the target of a `CNAME`, `MX`, `NS` or `PTR` record is the zone name. TXT values in the zone file form, one or more quoted chunks (`"v=spf1 \"a\" -all"`, `"v=spf1 a" " -all"`), are compared as the chunks joined without their quotes and escapes, since Cloudflare stores TXT content as it was sent and `v=spf1 "a" -all` is the same DNS record; any other value is compared exactly, quotes included (`prefix" "suffix` is not `prefixsuffix`). A TXT record stored in the quoted form and configured without quotes gets a one-time in-place update to the configured form after the import (the DNS answer does not change). An existing record is imported into one address only: configured records that differ only in `priority` (`MX`, `URI`) match the same existing record, which goes to the one with the same priority, while the others are created; without such a record, the import is ambiguous. In the same way, a record with a priority that matches several existing records (MX 10 and MX 20 on one host) takes the one with its priority. A record is imported only when its match is unambiguous. When it is not, for example when the zone has several identical records, `plan` stops (from 2.11.0; before, it showed a warning and planned the record as created) and lists the records with the IDs of all their matches. Remove the duplicates from the zone or give the records distinct values or priorities; to import such a record anyway, set `import_existing = false` and write an `import` block for it. The `import_duplicates` output has the same list.

## Writing the Configuration of an Existing Zone

The import adopts the records that the configuration describes, so a zone with many records needs that configuration first. `tools/zone-to-ezdns.py` (Python 3.8 or later, no packages) writes it from the records that the Cloudflare API returns:

```console
$ curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=5000000" > zone.json
$ python3 tools/zone-to-ezdns.py zone.json --zone example.com --default-ttl 3600 > records.ezdns.yaml
zone-to-ezdns: skipped NS example.com (372e67954025e0ba6aaa6d586b9e0b59): read only, managed by Cloudflare
```

For a zone with a proxied apex and `www`, two MX records on one host, an SPF record with a TTL of 300 and an SRV record, `records.ezdns.yaml` is:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/5xxeu/terraform-cloudflare-ezdns/v2.20.0/schema/records.schema.json
# Records of example.com written by zone-to-ezdns.py (6 records). Review them, then adopt them with
# import_existing = true and import blocks, and check that the plan creates and deletes nothing.
records:
  "@":
    A:
      - content: "192.0.2.10"
        proxied: true
    MX:
      - content: "mx.example.net"
        key: "priority-10"
        priority: 10
      - content: "mx.example.net"
        key: "priority-20"
        priority: 20
    TXT:
      - content: "\"v=spf1 mx -all\""
        ttl: 300
  "_sip._tcp":
    SRV:
      - data:
          priority: "10"
          weight: "5"
          port: "5060"
          target: "sip.example.com"
  "www":
    CNAME:
      - content: "example.com"
        proxied: true
```

The script exits with 1 when it skipped records or found copies (the file is written anyway), so a CI step can stop on it, and with 2 when the input cannot be read, has a record of an unexpected shape or is one page of a longer list (nothing is written).

- Every value is quoted, so YAML 1.1 keeps it as text. Records with the TTL of `--default-ttl` (the `default_ttl` of the module call) are written without one, proxied records without TTL. The proxy status of `A`, `AAAA` and `CNAME` records is written both ways (`proxied: false` too), so a `default_proxied = true` or the defaults of a group do not change a record of the zone.
- `MX` and `URI` records that differ only in priority, and `CAA` records that differ only in flags, get a `key` each, since they would have the same record key. When these keys repeat within a name and type (two MX hosts, each with priorities 10 and 20), the target goes into the key (`mx1.example.com-priority-10`). Copies of one record in the zone (also with another TTL, comment or tags) are written once and reported with their IDs, not their values (the value of a proxied record is its origin address): the import of such a record stops until the zone has one copy.
- Copies use the same comparisons as the module: TXT chunks and escapes, case and trailing dots in hostnames and hex, IPv6 spelling, numeric data fields and CAA issuer names. URI targets, base64, opaque TXT escapes and CAA parameters stay exact. The first copy keeps its spelling in YAML. Copies with different `proxied` values are all written for a manual choice.
- `--stable-keys` gives every record but a `CNAME` a `key` from its Cloudflare ID (`cf-` and the first 8 characters, `key: "cf-372e6795"`), also the records above. Without a `key`, the value is a part of the record key, so a new IP address or TXT value deletes the record and creates it again; with one, the change is an update in place. The key is only a name: it stays when the record is later recreated with another ID. A `CNAME` has no value in its key and needs none. A record without an ID in the input (a hand-written list) is written without a key and reported.
- The first line links the [JSON Schema](yaml.md#records-in-yaml) of the module release that the script comes with (its version in `CHANGELOG.md` next to `tools/`), so an editor offers only the fields of that release. `--schema` writes another link: a URL, or a path relative to the YAML file, such as `modules/ezdns/schema/records.schema.json` for a [local copy](sources.md#local-copy).
- Records that the module does not manage are left out and reported: read-only records of Cloudflare, records outside the zone and types that the module does not support.
- The output of [`unmanaged_records`](unmanaged-records.md#records-not-in-the-configuration) has the same form, without TTL, proxy status, comments and tags. Records written from it get the module defaults, so check them before the import: a proxied record written as not proxied would publish its origin address after the apply.

Then review the file, pass it to the module and adopt the records as described above; the plan must import every record and create none. Consider giving a `key` to records whose values will change (see [Record Keys](record-model.md#record-keys)), or write the file with `--stable-keys`.
