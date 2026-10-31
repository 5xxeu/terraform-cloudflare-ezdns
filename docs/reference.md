# Inputs and Outputs

Part of the documentation of [ezdns](../README.md).

## Inputs

Both wrappers take `zone_id`, `zone_name` (optional, looked up from `zone_id` when omitted; when set, it must be the name of that zone, see [Requirements](../README.md#requirements)), `records`, [`record_groups`](yaml.md#records-in-several-files), the [defaults](#defaults-comments-and-tags), `minimum_ttl`, `require_keys` (see [When to Use `key`](record-model.md#when-to-use-key)), `allowed_cname_conflicts` (see [Validation](validation.md#validation)) and [`owned_names`](unmanaged-records.md#the-part-of-the-zone-a-module-call-owns); the v5 wrapper also takes `import_existing`, `report_unmanaged`, `unmanaged_ignore` and `unmanaged_policy`. The [`compile`](testing.md#testing-your-records) submodule takes the inputs of the v4 wrapper without `zone_id`, with `zone_name` required, and the [`idna`](recipes.md#internationalized-names) submodule the inputs of the root module, with names in Unicode.

The type of `records` is shown as `any`: Terraform silently drops unknown attributes when it converts a value to an object type, so the module accepts the value as is, rejects unknown attributes, and then converts it to the typed structure described in [Record Object Schema](#record-object-schema). The full reference of inputs, outputs, requirements and resources is generated from the code with [terraform-docs](https://terraform-docs.io): [`modules/dns/v4`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/modules/dns/v4), [`modules/dns/v5`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/modules/dns/v5), [`modules/dns/compile`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/modules/dns/compile), [`modules/dns/idna`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/modules/dns/idna).

### Record Object Schema

| Field | Description | Default |
|-------|-------------|---------|
| `content` | IP address, hostname, or text value | `null` |
| `ttl` | Time to Live (automatically set to `1` if proxied) | `default_ttl` (`3600`) |
| `proxied` | Whether the record gets Cloudflare's proxy | `default_proxied` (`false`) for `A`, `AAAA`, `CNAME` and `ALIASES`, otherwise `false` |
| `priority` | Priority for MX and URI records | `null` |
| `tag` | Tag for CAA records (`issue`, `issuewild`, `iodef`) | `null` |
| `flags` | Flags for CAA records | `0` |
| `data` | Fields of structured records, see [Record Types](record-model.md#record-types) | `null` |
| `key` | Stable key used instead of the value in the record key, see [Record Keys](record-model.md#record-keys) | `null` |
| `comment` | Note shown in the Cloudflare dashboard | `default_comment` |
| `tags` | Tags such as `owner:web`, added to `default_tags` | `[]` |
| `settings` | `flatten_cname`, `ipv4_only` and `ipv6_only` (provider v5 only, ignored by the v4 wrapper with a warning) | `null` |
| `private_routing` | Private network routing to the origin of an `A`, `AAAA` or `CNAME` record (provider v5 only, ignored by the v4 wrapper with a warning) | `null` |
| `ignore_changes` | Attributes taken from the record in the zone, for values changed outside Terraform: `content`, `ttl`, `proxied`, `comment`, `tags`; see [Values Changed Outside Terraform](record-model.md#values-changed-outside-terraform) (provider v5 only) | `null` |

### Defaults, Comments and Tags

Values that most records share can be set once for the module call, and overridden per record:

| Input | Description | Default |
|-------|-------------|---------|
| `default_ttl` | TTL of records that do not set one | `3600` |
| `default_proxied` | Proxying of `A`, `AAAA`, `CNAME` and `ALIASES` records that do not set `proxied` (other types are never proxied) | `false` |
| `default_comment` | Comment of records that do not set one | `null` |
| `default_tags` | Tags added to the tags of every record | `[]` |

`null` for `default_ttl`, `default_proxied` or `default_tags` means the default, so a module call that passes them through from optional inputs does not have to replace `null` itself.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.21.0"

  zone_id         = var.zone_id
  zone_name       = "example.com"
  default_proxied = true
  default_comment = "Managed by Terraform"
  default_tags    = ["managed-by:terraform"]

  records = {
    # Proxied, with the default comment and tags
    "@" = { A = [{ content = "192.0.2.10" }] }

    "vpn" = {
      A = [{ content = "192.0.2.20", proxied = false, comment = "WireGuard" }]
    }
  }
}
```

Cloudflare supports record tags only on some plans and limits the length of comments by plan, see [DNS record comments and tags](https://developers.cloudflare.com/dns/manage-dns-records/reference/record-attributes/); on other plans, leave `default_tags` and `tags` empty.

## Outputs

- `record_names`: fully qualified names of all managed records (from the configuration, known at plan)
- `records`: managed records keyed by their [record key](record-model.md#record-keys), with `id`, `zone_id`, `name` (as Cloudflare returns it), `fqdn` (fully qualified and in lower case, from the configuration, so it is known at `plan`), `type`, `content`, `ttl`, `proxied`, `priority` and `data` (structured records, as configured). For other modules, e.g. monitoring of the names or certificates for them:

  ```hcl
  hosts = [for r in module.dns.records : r.fqdn if contains(["A", "AAAA", "CNAME"], r.type)]
  ```

  In a plan, everything but `id` (and `content` of structured records, which Cloudflare computes) is known:

  ```text
  + records = {
      + "app A 192.0.2.10"           = {
          + content  = "192.0.2.10"
          + data     = null
          + fqdn     = "app.example.com"
          + id       = (known after apply)
          + name     = "app"
          + priority = null
          + proxied  = false
          + ttl      = 3600
          + type     = "A"
          + zone_id  = "023e105f4ecef8ad9ca31a8372d0c353"
        }
      + "_sip._tcp SRV 9c61601f99e8" = {
          + content  = (known after apply)
          + data     = {
              + port     = "5060"
              + priority = "10"
              + target   = "sip.example.com"
              + weight   = "5"
            }
          + fqdn     = "_sip._tcp.example.com"
          + id       = (known after apply)
          + name     = "_sip._tcp"
          + priority = 10
          + proxied  = false
          + ttl      = 3600
          + type     = "SRV"
          + zone_id  = "023e105f4ecef8ad9ca31a8372d0c353"
        }
    }
  ```
- `state_migration`: map of the record keys used by 1.x to the current ones, see [Upgrading from v1](upgrading.md#from-v1-to-v2)
- `import_ids` (v5): import IDs of records that already exist in the zone, see [Importing Existing Records](importing.md#importing-existing-records)
- `import_duplicates` (v5): records that cannot be imported unambiguously, with the IDs of their matches; while there are any, `plan` stops
- `presumed_previous_records` (v5): with `report_unmanaged`, existing records taken as old values of records getting a new value in this apply, with `id`, `name` and `type`. They are left out of `unmanaged_records`; the module cannot see the state, so a record added by hand may be among them
- `matched_records` (v5): with `report_unmanaged`, existing records that configured records match (by value, or by name and type with `ignore_changes`), with `id`, `name` and `type`. They are left out of `unmanaged_records`; a copy of a configured record that the state does not hold may be among them, which [`tools/plan-guard.py --unmanaged`](plan-guard.md) finds
- `unmanaged_records` (v5): with `report_unmanaged`, the records of the zone that the configuration does not describe, see [Records Not in the Configuration](unmanaged-records.md#records-not-in-the-configuration)
