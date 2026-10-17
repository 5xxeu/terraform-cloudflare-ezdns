# DNS records without a provider

Checks and normalizes records like the wrappers do, without a provider and without resources: the same inputs (except `zone_id`, and `zone_name` is required), the same validation and warnings, and the records as the wrappers would create them, keyed by their record keys. Use it to test a configuration with `terraform test` and no Cloudflare credentials, for example that the zone keeps its MX records or that mail hosts are not proxied. See [Testing Your Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing-your-records) for an example.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_records"></a> [records](#module\_records) | ../records | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cname_conflicts"></a> [allowed\_cname\_conflicts](#input\_allowed\_cname\_conflicts) | Names where a CNAME already shares its name with other records in the zone, e.g. ["community", "*.legacy.example.com"]. Cloudflare accepts this for records that are not proxied, and older zones often have such names; only the listed names are exempt from the CNAME check. Compared fully qualified and case-insensitively; a second CNAME on a name still fails, and listed names without a conflict show a warning | `list(string)` | `[]` | no |
| <a name="input_default_comment"></a> [default\_comment](#input\_default\_comment) | Comment of records that do not set one, e.g. "Managed by Terraform" | `string` | `null` | no |
| <a name="input_default_proxied"></a> [default\_proxied](#input\_default\_proxied) | Whether A, AAAA, CNAME and ALIASES records that do not set proxied are proxied by Cloudflare | `bool` | `false` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags added to all records, e.g. ["managed-by:terraform"] (tags require a Cloudflare plan that supports them) | `list(string)` | `[]` | no |
| <a name="input_default_ttl"></a> [default\_ttl](#input\_default\_ttl) | TTL of records that do not set one (1 means automatic) | `number` | `3600` | no |
| <a name="input_minimum_ttl"></a> [minimum\_ttl](#input\_minimum\_ttl) | Lowest TTL other than 1 (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones: set 30 there, keep 60 otherwise, or "auto" to take it from the plan of the zone (one more API call, which needs Zone Read; the compile module, which reads nothing, takes 30) | `string` | `"60"` | no |
| <a name="input_owned_names"></a> [owned\_names](#input\_owned\_names) | The part of the zone that this module call manages: names in include and below them, except names in exclude and below them (e.g. include = ["apps"], exclude = ["k8s.apps"]). Configured records outside it fail at plan, and only existing records inside it are reported as unmanaged. Names like in records, compared fully qualified and case-insensitively, by whole labels ("apps" covers "x.apps", not "myapps"). null: the whole zone | <pre>object({<br/>    include = optional(list(string), ["@"])<br/>    exclude = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_record_groups"></a> [record\_groups](#input\_record\_groups) | Further records in named groups, each with defaults of its own:<br/>`record_groups[GROUP] = { records = RECORDS, defaults = { ttl, proxied, comment, tags } }`,<br/>where RECORDS has the form of `records` (e.g. one YAML file per group). The groups and<br/>`records` are merged by name and type: the lists of records are joined, and a record<br/>defined twice fails as a duplicate. A record's own value wins over the group default,<br/>which wins over the module default (`proxied` applies to A, AAAA, CNAME and ALIASES<br/>only; group tags are added to `default_tags` and the record's tags). The group name<br/>is not a part of the record keys, so moving a record between groups or into<br/>`records` keeps it in the state. | `any` | `{}` | no |
| <a name="input_records"></a> [records](#input\_records) | DNS records: `records[NAME][TYPE] = [RECORD, ...]`, where NAME is a name within the<br/>zone (`@` for the apex) and TYPE a record type, optionally with a prefix<br/>(`"_acme-challenge.TXT"`). Record attributes: `content`, `ttl`, `proxied`, `priority`,<br/>`tag`, `flags`, `data`, `key`, `comment`, `tags`, `settings` (`flatten_cname`,<br/>`ipv4_only`, `ipv6_only`), `private_routing` and `ignore_changes`. See the README for the details. Unknown attributes fail at plan. | `any` | `{}` | no |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Zone domain name (e.g. example.com), in Punycode for internationalized zones. A trailing dot is ignored | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_records"></a> [records](#output\_records) | The records as the wrappers would create them, keyed by their record key (the key of the Terraform address): name (as sent to Cloudflare), fqdn, type, content, ttl (1 for proxied records), proxied, comment, tags, settings, private\_routing, priority and data |
<!-- END_TF_DOCS -->
