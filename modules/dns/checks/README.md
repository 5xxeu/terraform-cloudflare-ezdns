# Checks over all records

Internal module used by `modules/dns/v5` and `modules/dns/compile` after the records core: fails the plan on the problems that `modules/dns/records` found over all records (`output.diagnostics` there: duplicates, records with the same value, low TTLs, missing keys, misplaced wildcards, long names, CNAMEs to their own name, records outside `owned_names`, CNAME conflicts), with one validated input per check, and passes `flat_records` on to the resources only after the checks. It has no provider dependency and is not meant to be used directly. See the [main README](https://github.com/5xxeu/terraform-cloudflare-ezdns#readme) for the input format.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cname_conflicts"></a> [cname\_conflicts](#input\_cname\_conflicts) | Names where a CNAME shares the name with other records, or with another CNAME | `list(string)` | n/a | yes |
| <a name="input_duplicates"></a> [duplicates](#input\_duplicates) | Records with the same key, or the same record written in different forms under different keys | `list(string)` | n/a | yes |
| <a name="input_flat_records"></a> [flat\_records](#input\_flat\_records) | output.flat\_records of modules/dns/records, passed through by output.flat\_records once all checks pass | `any` | n/a | yes |
| <a name="input_long_names"></a> [long\_names](#input\_long\_names) | Fully qualified names and alias targets longer than 253 characters | `list(string)` | n/a | yes |
| <a name="input_low_ttls"></a> [low\_ttls](#input\_low\_ttls) | TTLs below minimum\_ttl, and default\_ttl when it is below it | `list(string)` | n/a | yes |
| <a name="input_minimum_ttl"></a> [minimum\_ttl](#input\_minimum\_ttl) | The lowest TTL other than 1 that the records module checked against (60, or 30 on Enterprise zones), for the message of low\_ttls | `number` | n/a | yes |
| <a name="input_misplaced_wildcards"></a> [misplaced\_wildcards](#input\_misplaced\_wildcards) | Names and alias targets with a wildcard other than the whole leftmost label | `list(string)` | n/a | yes |
| <a name="input_missing_keys"></a> [missing\_keys](#input\_missing\_keys) | Records of the types in require\_keys without a key | `list(string)` | n/a | yes |
| <a name="input_not_owned"></a> [not\_owned](#input\_not\_owned) | Records outside owned\_names | `list(string)` | n/a | yes |
| <a name="input_owned_exclude"></a> [owned\_exclude](#input\_owned\_exclude) | Fully qualified names that owned\_names excludes, for the message of not\_owned | `list(string)` | n/a | yes |
| <a name="input_owned_include"></a> [owned\_include](#input\_owned\_include) | Fully qualified names that owned\_names includes (the zone name without owned\_names), for the message of not\_owned | `list(string)` | n/a | yes |
| <a name="input_same_values"></a> [same\_values](#input\_same\_values) | Records with the same name, type and value under different keys | `list(string)` | n/a | yes |
| <a name="input_self_cnames"></a> [self\_cnames](#input\_self\_cnames) | CNAME records (and aliases) that point to their own name | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_flat_records"></a> [flat\_records](#output\_flat\_records) | flat\_records as given, once every check has passed: the resources of the callers take their records from here, so a check put off until apply (a list known only after apply) fails before any record is created or changed |
<!-- END_TF_DOCS -->
