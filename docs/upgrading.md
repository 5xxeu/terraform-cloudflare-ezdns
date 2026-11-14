# Upgrading and Migration

Part of the documentation of [ezdns](../README.md).

## Upgrade Path

Do one step at a time, each with its own `terraform plan` and `apply`, and review every plan: it must not destroy or create records.

1. **From v1 to v2** (record keys): [v1 to v2](#from-v1-to-v2), staying on the submodule you already use. Targeting 2.6 or later, fix any [unknown attributes](#to-26-unknown-attributes) as part of this step.
2. **From provider v4 to v5**, if you use the `v4` submodule and want provider v5: [provider v4 to v5](#from-provider-v4-to-v5). Do it with the latest 2.x, or after step 4 with 3.x, which keeps the `v4` submodule. This step is optional: provider v4 stays supported in 3.x (see [Stability](../README.md#stability)).
3. **To the root module**, optionally: [v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module). From the `v4` submodule it is a step of its own, after step 2 is applied: do not combine the two moves.
4. **To 3.0**: [To 3.0](#to-30), from the latest 2.x, on the same submodule (`v4` stays `v4`).

Configurations that use the module from an earlier address (the repository `i386dev/terraform-cloudflare-easy-dns` or the Registry source `NikitaPuglachenko/easy-dns/cloudflare`) only change `source`, see [from an earlier address](#from-an-earlier-address).

For example, a configuration on `//modules/dns/v5` of v1 does step 1 with `RESOURCE=cloudflare_dns_record` and may stay on the submodule. From 2.0–2.5, upgrading to 2.6 or later only needs the [unknown attributes](#to-26-unknown-attributes) fixed, if there are any.

## From v1 to v2

Version 2 changes the record keys in the state (see [Record Keys](record-model.md#record-keys)). Without migration, Terraform would destroy and recreate every record. The `state_migration` output maps the old keys to the new ones, so the migration can be done with `moved` blocks:

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

## To 3.0

Version 3.0 has breaking changes, so go through the list before changing `version`. Upgrade from the latest 2.x (a configuration on 1.x goes through 2.x first, see the [upgrade path](#upgrade-path); a configuration on provider v4 stays on the `v4` submodule, which 3.x keeps), and fix what does not need 3.0 on 2.x already.

1. **Terraform 1.9.0 or later.** 3.0 requires Terraform 1.9.0 (2.x: 1.8.0); stay on 2.x to keep Terraform 1.8.
2. **Provider v4 stays.** The `v4` submodule is kept on the core of 3.0 with the same changes as the other modules, and a configuration on provider v4 goes to 3.0 on it, without moving to provider v5 at the same time. Do step 6 with the address of the v4 wrapper (`module.dns.cloudflare_record.record`), apply, and delete the file with the `moved` blocks. Moving to provider v5 comes afterwards, in 3.x, see [From Provider v4 to v5](#from-provider-v4-to-v5): one step from provider v4 on 2.x to provider v5 on 3.0 is not supported. `settings`, `private_routing` and `ignore_changes` still need provider v5.
3. [Unused attributes fail the plan](#unused-attributes-fail-the-plan): fix them on 2.x.
4. [ALIASES take `name`](#aliases-take-name-instead-of-content): rename the attribute.
5. [`records` is sensitive, `name` is the fully qualified name](#records-is-sensitive-name-is-the-fully-qualified-name): mark outputs that pass it on.
6. [Normalized record keys](#normalized-record-keys): generate `moved` blocks from `state_migration` for the records that change their key.

Steps 3 to 5 do not change the state. Run `terraform init -upgrade` and `terraform plan` after the changes: apart from step 6, the plan must not destroy or create records.

### Unused Attributes Fail the Plan

Attributes that do not apply to the type of a record (`content` of a record with `data`, `priority` other than on `MX` and `URI`, `tag` and `flags` other than on `CAA`) fail the plan; in 2.x they showed a warning. A configuration that plans on the latest 2.x without the warning "These attributes do not apply to the type of their record" is not affected. Otherwise remove the listed attributes, on 2.x or with the upgrade: they had no effect, so the records do not change. No addresses in the state change.

### ALIASES Take name Instead of content

An `ALIASES` record names the CNAME it creates in `name`; `content` on an `ALIASES` record fails the plan with the list of the records to change. Rename the attribute: `ALIASES = [{ content = "www" }]` becomes `ALIASES = [{ name = "www" }]`, and `- content: www` becomes `- name: www` in YAML, also in `record_groups` and for `"<prefix>.ALIASES"`. The JSON Schema (`schema/records.schema.json`) requires `name` for `ALIASES` as well. The CNAME, its key (`www CNAME`) and its target do not change, so no addresses in the state change.

### records Is Sensitive, name Is the Fully Qualified Name

The `records` output of the root module, the wrappers and `modules/dns/compile` is sensitive: `content` and `data` of a proxied record show the origin address that Cloudflare hides. What changes for a configuration that uses it:

- An output that passes `records` on needs `sensitive = true` next to its `value`, or Terraform rejects the configuration. Terraform 1.9.0 shows the value of an output that is not marked, so mark it on every version.
- `for_each` over `module.dns.records` fails ("Invalid for_each argument", sensitive value). Use `record_metadata`, a list of the records without values (`id`, `zone_id`, `name`, `fqdn`, `type`, `ttl`, `proxied`, `priority`, `comment`, `tags`), or `nonsensitive(module.dns.records)` where the addresses may be public. Expressions over `records` give sensitive results (`[for r in module.dns.records : r.fqdn]`): use `record_metadata` there too.
- `name` in `records` and `record_metadata` is the fully qualified name in lower case, the same as `fqdn`. It was the name as written right after `apply` (`app`) and the fully qualified name after the next refresh, which made a configuration that reads `name` change its result between the two. Read `name` as `fqdn` now. The names of the records in Cloudflare and in the state do not change.

No addresses in the state change.

### Normalized Record Keys

Record keys are built from the name in lower case and the value in a normal form (see [Record Keys](record-model.md#record-keys)), so forms that DNS does not tell apart have one address: `WWW` and `www`, `Mail.Example.com.` and `mail.example.com` as an `MX`, `NS` or `PTR` target, `2001:0DB8::1` and `2001:db8::1`, `5060.0` and `5060` in `data`. A record written in the normal form (names in lower case, targets without the trailing dot, IPv6 addresses shortened, numbers in their shortest form) keeps its key. The service parameters of `HTTPS` and `SVCB` records are not normalized: a record keeps its key with the parameters as fields of `data` and with them in `value`, and switching between the two still gives a new key. A record written in another form gets the key of the normal form, and without a `moved` block Terraform plans to delete it and create it again.

The `state_migration` output maps the 2.x keys of these records to their keys now (it held the 1.x keys in 2.x; upgrade from 1.x to 2.x first, see [From v1 to v2](#from-v1-to-v2)). Generate `moved` blocks from it (requires `jq`):

1. Change the module to version 3.0 and run `terraform init -upgrade`.
2. Set `ADDRESS` to the address of the records in the state, then generate the blocks:

   ```sh
   # The root module and modules/dns/idna; the //modules/dns/v5 submodule has no module.v5:
   # module.dns.cloudflare_dns_record.record. The //modules/dns/v4 submodule (provider v4):
   # module.dns.cloudflare_record.record
   ADDRESS=module.dns.module.v5.cloudflare_dns_record.record
   MODULE=${ADDRESS%.cloudflare_*record}; MODULE=${MODULE%.module.v[45]}
   echo "jsonencode(nonsensitive(${MODULE}.state_migration))" | terraform console | tail -n 1 \
     | jq -r --arg addr "$ADDRESS" '
         def key: tojson | gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{");
         fromjson | to_entries[] |
         "moved {",
         "  from = \($addr)[\(.key | key)]",
         "  to   = \($addr)[\(.value | key)]",
         "}", ""' \
     > dns_migration.tf
   ```

   `MODULE` is the module call whose output `state_migration` is read (`module.dns`, or `module.v4` for a call of the v4 submodule at `module.v4.cloudflare_record.record`): it is `ADDRESS` without the resource and without a `.module.v4` or `.module.v5` inside the call; the module call must be in the root module, where `terraform console` reads it. `key` writes a key as an HCL string and escapes `${` and `%{` (an explicit key may contain them), since the address of a `moved` block cannot hold a template. The output is sensitive (a key can hold the origin address of a proxied record), so the command reads it with `nonsensitive()`, and the generated file holds these keys as well: keep it out of public logs and delete it after `apply`. `tail -n 1` keeps the value: Terraform 1.9 prints warnings of the configuration to the same output. An empty `dns_migration.tf` means that no key changes.
3. Run `terraform plan`. It should only show records that have moved (and changes in place, if any), with no records to add or destroy.
4. Run `terraform apply`, then delete `dns_migration.tf`.

The map has every record written in another form, also when its state has the new key already (another state of the same configuration, or one applied before): a `moved` block whose old address is not in the state does nothing. Two records that are one record in another form (`WWW` and `www`) fail at `plan` as duplicates; they were duplicates in 2.x too.

## To 2.20: IPv4 Without Leading Zeros

A records and the `ipv4hint` of HTTPS and SVCB records now require four decimal
octets without leading zeros. Change values such as `192.000.002.001` to `192.0.2.1`
before upgrading. This tightens validation: a
configuration accepted by earlier releases can now fail at plan.

An explicit `key` keeps its Terraform address. Without one, changing the spelling
changes the address: add a `moved` block from the old address to the new one, then
check that the plan updates the existing record without creating or destroying it.
For example:

```hcl
moved {
  from = module.dns.module.v5.cloudflare_dns_record.record["app A 192.000.002.001"]
  to   = module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.1"]
}
```

Adjust the module address to your configuration; with provider v4 the resource is
`module.dns.cloudflare_record.record`. Record key generation itself is
unchanged; canonical inputs keep their existing addresses.

## To 2.17: plan-guard Rejects Incomplete Plans

> **CI steps that check targeted plans:** add `--allow-incomplete` to the `plan-guard.py` command.

[plan-guard](plan-guard.md) now exits with status 2 on errored plans, on a `format_version` other than `1.N` and on incomplete plans. Terraform marks every plan made with `-target` as incomplete. `--allow-incomplete` lets the usual checks run on these plans; errored plans and unsupported format versions are still rejected.

## To 2.16.1: Lists in records and record_groups

> **Configurations that pass a list as `record_groups` (`record_groups: []` in YAML):** `plan` now fails. Pass `{}` or leave `record_groups` out.

Such a list passed the validations as no groups, so the plan deleted every record of the groups. A list in `records` failed before too, with an error of `keys()`; the message now says what to change.

## To 2.13: Ranges of Data Fields, Unused Attributes

> **Configurations with out-of-range `data` values:** `plan` now fails for them, e.g. an SRV `port` of 70000 or a CAA `flags` of 256.

Numeric fields of structured records are checked against their ranges (see [Validation](validation.md#validation)). Such values were rejected by the Cloudflare API at apply before, so a configuration that applies today is not affected, unless it has a record that has never been applied. Attributes that do not apply to the type of a record (`content` of an SRV record, `priority` of an A record, `tag` of a TXT record) now show a warning; they were ignored before and still are, and fail from [3.0](#unused-attributes-fail-the-plan), so remove them.

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

Since 2.6, a record attribute that the module does not know fails the plan, e.g. `records["app"]["A"][0]: unknown attribute "proxid"`. Before, Terraform silently dropped such attributes, so a misspelled optional attribute had no effect. Fix the reported attributes: the plan then shows whether the corrected attributes change any records (e.g. a record that was meant to be proxied). For records in YAML, the [JSON Schema](yaml.md#records-in-yaml) highlights these mistakes in the editor.

## From Provider v4 to v5

This step is optional: the `v4` submodule is supported in 3.x as long as Cloudflare releases provider v4 versions. It works with the latest 2.x and with 3.x, but not from provider v4 on 2.x straight to provider v5 on 3.0: first upgrade to 3.0 on the `v4` submodule, apply the `moved` blocks of [To 3.0](#normalized-record-keys) (if there were any) and delete their file, and only then switch to v5.

The v5 wrapper contains a `moved` block from `cloudflare_record` to `cloudflare_dns_record` (`modules/dns/v5/migrate-from-v4.tf`), so the state is migrated without recreating records:

1. Upgrade the Cloudflare provider to `~> 5.26`. The file with the `moved` blocks of [To 3.0](#normalized-record-keys) (`dns_migration.tf`) must be deleted after its `apply` and before the switch: it holds addresses of `cloudflare_record`.
2. Change the module `source` from `//modules/dns/v4` to `//modules/dns/v5`, keeping the module name the same.
3. Run `terraform init -upgrade` and `terraform plan`. The plan should only show moved resources, without destroying or creating records; provider v5 also plans a one-time in-place update of the moved records (e.g. CAA `flags` become numbers). Review it carefully before applying.
4. Run `terraform apply`. Provider v5 (checked with 5.26) may report `Provider produced inconsistent result after apply` with `.modified_on` for some records: the timestamp in the migrated state has a different precision ([cloudflare/terraform-provider-cloudflare#7387](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387)). The records are updated anyway; run `terraform plan` again, it should show no changes.

To end up on the root module, do it as a separate step after this one is applied: follow [From the v5 Submodule to the Root Module](#from-the-v5-submodule-to-the-root-module). Staying on the `v5` submodule is fine as well.

## From an Earlier Address

Up to 2.12.0, the module was developed in `i386dev/terraform-cloudflare-easy-dns`, and up to 2.6.0 it was published on the Terraform Registry as `NikitaPuglachenko/easy-dns/cloudflare`, which is no longer available. The repository now is `5xxeu/terraform-cloudflare-ezdns`, with all earlier tags, and the Registry source is `5xxeu/ezdns/cloudflare`. Git sources of the old repository and the archives of its releases keep working, but new versions are published only here.

Change `source` to the [Terraform Registry](../README.md#terraform-registry) (with `version`), a [Git source](sources.md#git-source) of the new repository or a [local copy](sources.md#local-copy) of the same version, keeping the module name and the path (root module, `//modules/dns/v5` or `//modules/dns/v4`): the module is the same, so no addresses in the state change. Run `terraform init -upgrade`, and `terraform plan` shows no changes. The module is now called ezdns: the README suggests `modules/ezdns` for a local copy and `*.ezdns.yaml` for records in YAML, but an existing copy in `modules/easy-dns` and existing `*.easy-dns.yaml` mappings keep working, since neither affects the state.

## From the v5 Submodule to the Root Module

The root module wraps the v5 submodule, so its records have one more level in their address. When switching `source` from the `v5` submodule (`./modules/ezdns/modules/dns/v5` or `//modules/dns/v5` in a Git source) to the root module, add a `moved` block next to the module call, so the records are not recreated:

```hcl
moved {
  from = module.dns.cloudflare_dns_record.record
  to   = module.dns.module.v5.cloudflare_dns_record.record
}
```

Run `terraform init -upgrade` and `terraform plan`: it should only show records that have moved. After `terraform apply`, the `moved` block can be removed. Staying on the submodule is fine as well.
