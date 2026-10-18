# Upgrading and Migration

Part of the documentation of [ezdns](../README.md).

## Upgrade Path

Do one step at a time, each with its own `terraform plan` and `apply`, and review every plan: it must not destroy or create records.

1. **From v1 to v2** (record keys): [v1 to v2](#from-v1-to-v2), staying on the submodule you already use. Targeting 2.6 or later, fix any [unknown attributes](#to-26-unknown-attributes) as part of this step.
2. **From provider v4 to v5**, if you use the `v4` submodule: [provider v4 to v5](#from-provider-v4-to-v5).
3. **To the root module**, optionally: [v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module).

Configurations that use the module from an earlier address (the repository `i386dev/terraform-cloudflare-easy-dns` or the Registry source `NikitaPuglachenko/easy-dns/cloudflare`) only change `source`, see [from an earlier address](#from-an-earlier-address).

For example, a configuration on `//modules/dns/v5` of v1 does step 1 with `RESOURCE=cloudflare_dns_record` and may stay on the submodule. From 2.0–2.5, upgrading to 2.6 or later only needs the [unknown attributes](#to-26-unknown-attributes) fixed, if there are any.

## From v1 to v2

Version 2 changes the record keys in the state (see [Record Keys](../README.md#record-keys)). Without migration, Terraform would destroy and recreate every record. The `state_migration` output maps the old keys to the new ones, so the migration can be done with `moved` blocks:

1. Change the module to version 2.x (replace the local copy, or change `?ref=` of a Git source), keeping the same submodule (`//modules/dns/v4` or `//modules/dns/v5`), and run `terraform init -upgrade`. With 2.6 or later, fix any [unknown attributes](#to-26-unknown-attributes) first, otherwise `terraform console` in the next step fails.
2. Generate `moved` blocks (requires `jq`). Set `MODULE` to the module address and `RESOURCE` to `cloudflare_record` for the `v4` submodule or `cloudflare_dns_record` for the `v5` submodule (version 1 had no root module):

   ```sh
   MODULE=module.dns
   RESOURCE=cloudflare_record
   echo "jsonencode(${MODULE}.state_migration)" | terraform console \
     | jq -r --arg addr "$MODULE.$RESOURCE.record" '
         fromjson | to_entries[] |
         "moved {",
         "  from = \($addr)[\(.key | tojson)]",
         "  to   = \($addr)[\(.value | tojson)]",
         "}", ""' \
     > dns_migration.tf
   ```

3. Run `terraform plan`. It should only show records that have moved, with no records to add or destroy.
4. Run `terraform apply`, then delete `dns_migration.tf`. The next `terraform plan` should show no changes.

## To 2.16.1: Lists in records and record_groups

> **Configurations that pass a list as `record_groups` (`record_groups: []` in YAML):** `plan` now fails. Pass `{}` or leave `record_groups` out.

Such a list passed the validations as no groups, so the plan deleted every record of the groups. A list in `records` failed before too, with an error of `keys()`; the message now says what to change.

## To 2.13: Ranges of Data Fields, Unused Attributes

> **Configurations with out-of-range `data` values:** `plan` now fails for them, e.g. an SRV `port` of 70000 or a CAA `flags` of 256.

Numeric fields of structured records are checked against their ranges (see [Validation](../README.md#validation)). Such values were rejected by the Cloudflare API at apply before, so a configuration that applies today is not affected, unless it has a record that has never been applied. Attributes that do not apply to the type of a record (`content` of an SRV record, `priority` of an A record, `tag` of a TXT record) now show a warning; they were ignored before and still are, and will fail from 3.0, so remove them.

The `records` output has more attributes (`zone_id`, `fqdn`, `ttl`, `proxied`, `priority`, `data`), and the lookups of `import_existing` and `report_unmanaged` read up to 100,000 records per type instead of 10,000. No addresses in the state change.

## To 2.11: Ambiguous Imports Stop the Plan

> **Configurations with `import_existing = true`:** if `plan` showed a warning about records that match several existing records, or about a lookup that returned 10,000 records, it now fails with the same list.

An ambiguous import used to plan the record as created, which fails at apply or leaves two copies of it in the zone. Remove the duplicates from the zone, give the records distinct values or priorities, or set `import_existing = false` and adopt these records with `import` blocks; see [Importing Existing Records](importing.md#importing-existing-records). Configurations without `import_existing`, and those whose plans showed no such warning, are not affected.

## To 2.8: Minimum TTL

> **Enterprise zones with TTLs from 30 to 59 seconds:** set `minimum_ttl = 30` in the module call before upgrading, or the plan fails.

TTLs below 60 seconds (other than `1`, automatic) are rejected at `plan` unless `minimum_ttl = 30`. Cloudflare accepts them only on Enterprise zones, so on other plans such a TTL already failed at the API; now the plan says what to change. The module cannot see the plan of a zone without an extra API call, hence the explicit setting.

## To 2.7: Names in Lower Case

Record names are sent in lower case, as Cloudflare stores them. With provider v5, a name written in another case (`M1._domainkey`) showed a change on every plan that `apply` did not settle; that diff is gone. With the v4 wrapper, such a record gets a one-time in-place update of its name. Keys keep the name as written, so no state address changes.

## To 2.6: Unknown Attributes

Since 2.6, a record attribute that the module does not know fails the plan, e.g. `records["app"]["A"][0]: unknown attribute "proxid"`. Before, Terraform silently dropped such attributes, so a misspelled optional attribute had no effect. Fix the reported attributes: the plan then shows whether the corrected attributes change any records (e.g. a record that was meant to be proxied). For records in YAML, the [JSON Schema](../README.md#records-in-yaml) highlights these mistakes in the editor.

## From Provider v4 to v5

The v5 wrapper contains a `moved` block from `cloudflare_record` to `cloudflare_dns_record`, so the state is migrated without recreating records:

1. Upgrade the Cloudflare provider to `~> 5.26`.
2. Change the module `source` from `//modules/dns/v4` to `//modules/dns/v5`, keeping the module name the same. To go straight to the root module, also add the `moved` block from [the v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module), with `cloudflare_record` in `from`.
3. Run `terraform init -upgrade` and `terraform plan`. The plan should only show moved resources, without destroying or creating records; provider v5 also plans a one-time in-place update of the moved records (e.g. CAA `flags` become numbers). Review it carefully before applying.
4. Run `terraform apply`. Provider v5 (checked with 5.26) may report `Provider produced inconsistent result after apply` with `.modified_on` for some records: the timestamp in the migrated state has a different precision ([cloudflare/terraform-provider-cloudflare#7387](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387)). The records are updated anyway; run `terraform plan` again, it should show no changes.

## From an Earlier Address

Up to 2.12.0, the module was developed in `i386dev/terraform-cloudflare-easy-dns`, and up to 2.6.0 it was published on the Terraform Registry as `NikitaPuglachenko/easy-dns/cloudflare`, which is no longer available. The repository now is `5xxeu/terraform-cloudflare-ezdns`, with all earlier tags, and the Registry source is `5xxeu/ezdns/cloudflare`. Git sources of the old repository and the archives of its releases keep working, but new versions are published only here.

Change `source` to the [Terraform Registry](../README.md#terraform-registry) (with `version`), a [Git source](../README.md#git-source) of the new repository or a [local copy](../README.md#local-copy) of the same version, keeping the module name and the path (root module or `//modules/dns/v4`, `//modules/dns/v5`): the module is the same, so no addresses in the state change. Run `terraform init -upgrade`, and `terraform plan` shows no changes. The module is now called ezdns: the README suggests `modules/ezdns` for a local copy and `*.ezdns.yaml` for records in YAML, but an existing copy in `modules/easy-dns` and existing `*.easy-dns.yaml` mappings keep working, since neither affects the state.

## From the v5 Submodule to the Root Module

The root module wraps the v5 submodule, so its records have one more level in their address. When switching `source` from the `v5` submodule (`./modules/ezdns/modules/dns/v5` or `//modules/dns/v5` in a Git source) to the root module, add a `moved` block next to the module call, so the records are not recreated:

```hcl
moved {
  from = module.dns.cloudflare_dns_record.record
  to   = module.dns.module.v5.cloudflare_dns_record.record
}
```

Run `terraform init -upgrade` and `terraform plan`: it should only show records that have moved. After `terraform apply`, the `moved` block can be removed. Staying on the submodule is fine as well.
