# Preparation of records

Internal module used by `modules/dns/v5` and `modules/dns/compile` before the records core: merges `record_groups` into `records`, with the defaults of each group and the source of each grouped record for error messages, and checks the values as given (the records core converts them to a type, which loses how they were written): attributes that do not apply to the type of their record fail, text values given as numbers show a warning. It has no provider dependency and is not meant to be used directly. See the [main README](https://github.com/5xxeu/terraform-cloudflare-ezdns#readme) for the input format.

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
| <a name="input_record_groups"></a> [record\_groups](#input\_record\_groups) | The record\_groups input of the calling module, as given (record\_groups[GROUP] = { records = RECORDS, defaults = { ttl, proxied, comment, tags } }) | `any` | `{}` | no |
| <a name="input_records"></a> [records](#input\_records) | The records input of the calling module, as given (records[NAME][TYPE] = [RECORD, ...]) | `any` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_all_records"></a> [all\_records](#output\_all\_records) | records with the records of record\_groups merged in, in the form of the records input and with the values as given (not converted to a type): grouped records have the defaults of their group and their source for error messages |
<!-- END_TF_DOCS -->