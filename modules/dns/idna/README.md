# DNS records with internationalized names

The v5 wrapper for zones and names in Unicode (`münchen.de`, `bücher`): converts `zone_name`, the names, prefixes of record types and targets that have non-ASCII characters to Punycode with `provider::idna::to_ascii` of the [`5xxeu/idna`](https://registry.terraform.io/providers/5xxeu/idna/latest) provider, and passes everything to the v5 wrapper. It has the inputs and outputs of the root module, and its records have the same addresses. See [Internationalized Names](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#internationalized-names) for usage.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.26 |
| <a name="requirement_idna"></a> [idna](#requirement\_idna) | ~> 0.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.26 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_v5"></a> [v5](#module\_v5) | ../v5 | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cname_conflicts"></a> [allowed\_cname\_conflicts](#input\_allowed\_cname\_conflicts) | Names where a CNAME already shares its name with other records in the zone, e.g. ["community", "*.legacy.example.com"]. Cloudflare accepts this for records that are not proxied, and older zones often have such names; only the listed names are exempt from the CNAME check. Compared fully qualified and case-insensitively; a second CNAME on a name still fails, and listed names without a conflict show a warning | `list(string)` | `[]` | no |
| <a name="input_default_comment"></a> [default\_comment](#input\_default\_comment) | Comment of records that do not set one, e.g. "Managed by Terraform" | `string` | `null` | no |
| <a name="input_default_proxied"></a> [default\_proxied](#input\_default\_proxied) | Whether A, AAAA, CNAME and ALIASES records that do not set proxied are proxied by Cloudflare | `bool` | `false` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags added to all records, e.g. ["managed-by:terraform"] (tags require a Cloudflare plan that supports them) | `list(string)` | `[]` | no |
| <a name="input_default_ttl"></a> [default\_ttl](#input\_default\_ttl) | TTL of records that do not set one (1 means automatic) | `number` | `3600` | no |
| <a name="input_import_existing"></a> [import\_existing](#input\_import\_existing) | Look up records that already exist in the zone and expose their IDs in the import\_ids output, to adopt them with import blocks. Requires the DNS Read permission | `bool` | `false` | no |
| <a name="input_minimum_ttl"></a> [minimum\_ttl](#input\_minimum\_ttl) | Lowest TTL other than 1 (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones: set 30 there, keep 60 otherwise, or "auto" to take it from the plan of the zone (one more API call, which needs Zone Read; the compile module, which reads nothing, takes 30) | `string` | `"60"` | no |
| <a name="input_owned_names"></a> [owned\_names](#input\_owned\_names) | The part of the zone that this module call manages: names in include and below them, except names in exclude and below them (e.g. include = ["apps"], exclude = ["k8s.apps"]). Configured records outside it fail at plan, and only existing records inside it are reported as unmanaged. Names like in records (in Unicode or Punycode; checked after the conversion), compared fully qualified and case-insensitively, by whole labels ("apps" covers "x.apps", not "myapps"). null: the whole zone | <pre>object({<br/>    include = optional(list(string), ["@"])<br/>    exclude = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_record_groups"></a> [record\_groups](#input\_record\_groups) | Further records in named groups, each with defaults of its own:<br/>`record_groups[GROUP] = { records = RECORDS, defaults = { ttl, proxied, comment, tags } }`,<br/>where RECORDS has the form of `records` (e.g. one YAML file per group). The groups and<br/>`records` are merged by name and type: the lists of records are joined, and a record<br/>defined twice fails as a duplicate. A record's own value wins over the group default,<br/>which wins over the module default (`proxied` applies to A, AAAA, CNAME and ALIASES<br/>only; group tags are added to `default_tags` and the record's tags). The group name<br/>is not a part of the record keys, so moving a record between groups or into<br/>`records` keeps it in the state. | `any` | `{}` | no |
| <a name="input_records"></a> [records](#input\_records) | DNS records: `records[NAME][TYPE] = [RECORD, ...]`, where NAME is a name within the<br/>zone (`@` for the apex) and TYPE a record type, optionally with a prefix<br/>(`"_acme-challenge.TXT"`). Record attributes: `content`, `ttl`, `proxied`, `priority`,<br/>`tag`, `flags`, `data`, `key`, `comment`, `tags`, `settings` (`flatten_cname`,<br/>`ipv4_only`, `ipv6_only`), `private_routing` and `ignore_changes`. See the README for the details. Unknown attributes fail at plan. | `any` | `{}` | no |
| <a name="input_report_unmanaged"></a> [report\_unmanaged](#input\_report\_unmanaged) | Look up the records of all types in the zone and report those that the configuration does not describe, in the unmanaged\_records output and a plan warning. Nothing is deleted. Requires the DNS Read permission (one request per record type) | `bool` | `false` | no |
| <a name="input_require_keys"></a> [require\_keys](#input\_require\_keys) | Record types whose records must have a key, e.g. ["A", "AAAA", "TXT"]: a record of these types without a key fails at plan. Without a key, a record is addressed by its value, so a new value deletes the record and creates a new one. CNAME and ALIASES are keyed by name, so they cannot be listed | `list(string)` | `[]` | no |
| <a name="input_unmanaged_ignore"></a> [unmanaged\_ignore](#input\_unmanaged\_ignore) | With report\_unmanaged: existing records that are expected in the zone and left out of the report, e.g. the TXT ownership records of external-dns: a record is left out when it matches all fields of an entry. name\_regex is matched (RE2, unanchored: use ^ and $) against the fully qualified name in lower case without a trailing dot, types lists record types | <pre>list(object({<br/>    name_regex = optional(string)<br/>    types      = optional(list(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_unmanaged_policy"></a> [unmanaged\_policy](#input\_unmanaged\_policy) | What report\_unmanaged does when the zone has records that the configuration does not describe: "warn" shows a plan warning, "error" stops the plan with the same list (e.g. in CI, for a part of the zone that only this configuration may change) | `string` | `"warn"` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare Zone ID | `string` | n/a | yes |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Zone domain name (e.g. example.com or münchen.de), in Unicode or Punycode. If null, it is looked up from zone\_id and converted to Punycode. A trailing dot is ignored | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_import_duplicates"></a> [import\_duplicates](#output\_import\_duplicates) | Cloudflare record IDs of existing records that a configured record cannot be matched to unambiguously, keyed by record key. Empty unless import\_existing is true; while there are any, the plan stops with this list |
| <a name="output_import_ids"></a> [import\_ids](#output\_import\_ids) | Import IDs (<zone\_id>/<record\_id>) of records that already exist in the zone, keyed by record key. Empty unless import\_existing is true; records with no match are left out, and ambiguous matches stop the plan |
| <a name="output_presumed_previous_records"></a> [presumed\_previous\_records](#output\_presumed\_previous\_records) | Existing records without a match taken as the old values of records that get a new value in this apply (left out of unmanaged\_records), with id, name and type. The module cannot see the state, so a record added by hand may be among them. Empty unless report\_unmanaged is true |
| <a name="output_record_names"></a> [record\_names](#output\_record\_names) | Fully qualified names of all managed records (lower case, from the configuration, so known at plan; one per record) |
| <a name="output_records"></a> [records](#output\_records) | Managed records keyed by their stable identifier: id, zone\_id, name (as returned by Cloudflare), fqdn (fully qualified, lower case, from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags, settings and private\_routing (the last two with provider v5, null with v4), the last five as configured (for a record with ignore\_changes, the listed attributes as in the zone), e.g. for monitoring or certificates of these names |
| <a name="output_state_migration"></a> [state\_migration](#output\_state\_migration) | Map of record keys used by module versions 1.x to the current keys, for state migration |
| <a name="output_unmanaged_records"></a> [unmanaged\_records](#output\_unmanaged\_records) | Records in the zone that the configuration does not describe (id, name, type, content, priority, data). Empty unless report\_unmanaged is true. Sensitive: the content of a proxied record is the origin address that Cloudflare hides |
<!-- END_TF_DOCS -->
