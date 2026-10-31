# Records in YAML

Part of the documentation of [ezdns](../README.md).

Records can be kept in a YAML file and passed with `yamldecode`. The file has the form of `records` under a `records` key:

```yaml
# records.ezdns.yaml
records:
  "@":
    A:
      - { content: "192.0.2.1", proxied: true }
    MX:
      - { content: "mx.example.net", priority: 10 }
    "_dmarc.TXT":
      - content: "v=DMARC1; p=reject"
  app:
    A:
      - content: "192.0.2.10"
    ALIASES:
      - content: "www"
  _sip._tcp:
    SRV:
      - data: { priority: 10, weight: 5, port: 5060, target: "sip.example.com" }
```

```hcl
records = yamldecode(file("${path.module}/records.ezdns.yaml")).records
```

`schema/records.schema.json` is a JSON Schema for such a file (a document with a `records` key). Editors use it for completion of record types, attributes and `data` fields, and highlight mistakes such as `proxid`, `ttl: 5m` or a CAA `tag` that does not exist before `terraform plan`. With a [local copy](sources.md#local-copy), the schema is at `modules/ezdns/schema/records.schema.json`.

Name the files `*.ezdns.yaml` (e.g. `records.ezdns.yaml`) and map this pattern to the schema once:

- **JetBrains IDEs**: Settings, Languages & Frameworks, Schemas and DTDs, JSON Schema Mappings: add the schema file with the file path pattern `*.ezdns.yaml`.
- **VS Code** (with the YAML extension): in the workspace settings,

  ```json
  "yaml.schemas": {
    "./modules/ezdns/schema/records.schema.json": "*.ezdns.yaml"
  }
  ```

Alternatively, a comment at the top of a file links the schema regardless of its name (the path is relative to the file):

```yaml
# yaml-language-server: $schema=modules/ezdns/schema/records.schema.json
```

See [`examples/yaml`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/examples/yaml). For several files, use [`record_groups`](#records-in-several-files) rather than `merge()`.

Use the schema of the module version you use. For records written in HCL, there is no such completion (see [HCL or YAML](../README.md#hcl-or-yaml)); mistakes are reported at `plan`.

**Quote text values.** `yamldecode` follows YAML 1.1, where unquoted `yes`, `no`, `on`, `off`, `y` and `n` (in any case) are booleans and `0123` or `1.10` are numbers; Terraform would turn them into `"false"`, `"123"` or `"1.1"` without an error. The module rejects booleans in `content`, `key`, `comment`, `tag`, `tags` and the fields of `data`, and warns about numbers in them (in `data`, only in the text fields such as `target`, `value` or `digest`; `port` or `priority` may be numbers). The unquoted `N` of a LOC `lat_direction` is accepted. Quoted, values stay as written:

```yaml
TXT:
  - content: "off"     # not: content: off  ->  "false"
  - content: "0123"    # not: content: 0123 ->  "123"
```

## Records in Several Files

`merge()` of two decoded YAML files is shallow: when both have records on `"@"`, the second file replaces all `"@"` records of the first, without an error. `record_groups` merges them instead, by name and type, and each group can have defaults of its own:

```yaml
# mail.ezdns.yaml
records:
  "@":
    MX:
      - { content: "mx1.mail.example.net", priority: 10 }
      - { content: "mx2.mail.example.net", priority: 20 }
    TXT:
      - content: "v=spf1 include:_spf.mail.example.net -all"
  "_dmarc":
    TXT:
      - { content: "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com", ttl: 300 }
```

```yaml
# web.ezdns.yaml
records:
  "@":
    A:
      - content: "192.0.2.10"
    ALIASES:
      - content: "www"
  "status":
    CNAME:
      - { content: "status.provider.example.net", proxied: false }
```

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.21.0"

  zone_id      = var.zone_id
  zone_name    = "example.com"
  default_tags = ["managed-by:terraform"]

  record_groups = {
    mail = {
      defaults = { comment = "mail", tags = ["team:mail"] }
      records  = yamldecode(file("${path.module}/mail.ezdns.yaml")).records
    }
    web = {
      # ttl applies to the records that are not proxied (status); proxied ones get 1
      defaults = { ttl = 300, proxied = true, comment = "web" }
      records  = yamldecode(file("${path.module}/web.ezdns.yaml")).records
    }
  }
}
```

Both files have records on `"@"`, and all of them are kept, each with the defaults of its group:

| Record key | TTL | Proxied | Comment | Tags |
|:-----------|----:|:--------|:--------|:-----|
| `@ A 192.0.2.10` | 1 | yes | web | `managed-by:terraform` |
| `@ MX mx1.mail.example.net` | 3600 | no | mail | `managed-by:terraform`, `team:mail` |
| `@ MX mx2.mail.example.net` | 3600 | no | mail | `managed-by:terraform`, `team:mail` |
| `@ TXT dd970e4a51a4` | 3600 | no | mail | `managed-by:terraform`, `team:mail` |
| `_dmarc TXT aa5f2cb9dc07` | 300 | no | mail | `managed-by:terraform`, `team:mail` |
| `status CNAME` | 300 | no | web | `managed-by:terraform` |
| `www CNAME` | 1 | yes | web | `managed-by:terraform` |

Proxied records get TTL 1 (automatic) whatever the default; `status` sets `proxied: false` itself, and `_dmarc` its own TTL. With the same MX record also in `records`, the plan fails:

```text
Error: Module output value precondition failed

Duplicate records (remove the duplicates or set a unique key for each of
them; MX records that differ only in priority and CAA records that differ
only in flags have the same key and need a key too):
"@ MX mx1.mail.example.net" from records["@"]["MX"][0] and
record_groups["mail"].records["@"]["MX"][0]
```

- The lists of records of the same name and type are joined: `records` first, then the groups in the order of their names. A record that two groups (or a group and `records`) define fails as a duplicate, with both sources, and every error names the group of a record.
- `defaults` takes `ttl`, `proxied`, `comment` and `tags`. A record's own value wins over the group default, which wins over the module default (`default_ttl`, ...). `proxied` applies to `A`, `AAAA`, `CNAME` and `ALIASES` records only; group tags are added to `default_tags` and the record's tags.
- The group name is not a part of the [record keys](record-model.md#record-keys): moving a record from one group to another, or between a group and `records`, keeps it in the state. Changing a group default changes the records of the group in place.
- `records` can be left out when every record is in a group. The checks of the module (CNAME conflicts, duplicates in different name forms, ...) see all records together.
