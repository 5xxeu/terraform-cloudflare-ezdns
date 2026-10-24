# Cloudflare DNS Records Factory (Terraform Module)

[![Release](https://img.shields.io/github/v/release/5xxeu/terraform-cloudflare-ezdns)](https://github.com/5xxeu/terraform-cloudflare-ezdns/releases/latest) [![Terraform Registry](https://img.shields.io/terraform/module/dt/5xxeu/ezdns/cloudflare?label=terraform%20registry&logo=terraform)](https://registry.terraform.io/modules/5xxeu/ezdns/cloudflare/latest) [![CI](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/ci.yml/badge.svg)](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/ci.yml) [![End-to-end](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/e2e.yml/badge.svg)](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/e2e.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/LICENSE)

Predictable Cloudflare DNS management with Terraform. The zone (or a part of it) is one map of names and record types instead of a resource per record, and the module adds what plain resources leave to review:

- **Stable state addresses**: a record with a `key` keeps its address when its value changes, and keys do not change within 2.x.
- **Checks before apply**: mistakes in names, types, values and conflicting records fail at `plan`, before the Cloudflare API.
- **Import of an existing zone**: records that are already in the zone are adopted instead of created again.
- **Checks of dangerous changes**: a script for CI stops plans that delete or replace records or turn off the proxy.
- **Tested upgrades**: the upgrade from the previous release and from provider v4 to v5 run against a real zone before each release; `moved` blocks for renamed records are written from a plan.

What is guaranteed and what is a best-effort check is listed in [Guarantees and Limits](#guarantees-and-limits).

## How It Works in 30 Seconds

The zone is described as one map, grouped by name and then by record type:

```
records[<name>][<TYPE>] = [ <record>, ... ]
```

| Key | Meaning |
|:----|:--------|
| `<name>` | A name within the zone: `app`, `app.example.com`, `@` (apex), `*.app` (wildcard) |
| `<TYPE>` | A record on `<name>`: `A`, `TXT`, `MX`, ... |
| `<prefix>.<TYPE>` | A record on `<prefix>.<name>`: `"_acme-challenge.TXT"` |
| `ALIASES` | CNAMEs named by each `content`, pointing to `<name>` |
| `<prefix>.ALIASES` | CNAMEs named by each `content`, pointing to `<prefix>.<name>` |

Each record becomes one Cloudflare DNS record, with a stable address in the Terraform state:

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.18.0"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "app" = {
      # app.example.com
      A = [{ key = "web", content = "192.0.2.10" }]

      # _acme-challenge.app.example.com
      "_acme-challenge.TXT" = [{ key = "acme", content = "token" }]

      # www.example.com -> CNAME -> app.example.com
      ALIASES = [{ content = "www" }]
    }
  }
}
```

`terraform plan` shows one resource per record:

```text
  # module.dns.module.v5.cloudflare_dns_record.record["_acme-challenge.app TXT acme"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["app A web"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["www CNAME"] will be created

Plan: 3 to add, 0 to change, 0 to destroy.
```

Each record is an instance of `module.dns.module.v5.cloudflare_dns_record.record`, with these keys:

| Record | Key in the state |
|:-------|:-----------------|
| `app.example.com A 192.0.2.10` | `app A web` |
| `_acme-challenge.app.example.com TXT "token"` | `_acme-challenge.app TXT acme` |
| `www.example.com CNAME app.example.com` | `www CNAME` |

- **Names**: `"app"` is the name within the zone (`"@"` for the apex). A prefix before the type (`"_acme-challenge.TXT"`) is added to the name.
- **Addresses**: a record without `key` is addressed by its value (`_acme-challenge.app TXT ee977806d728` without `key = "acme"`), so adding or removing records in a list leaves the others alone, but a changed value is a new record (the old one is deleted, the new one created, in no fixed order). With `key`, the key takes the place of the value in the address: a new value is an update in place, without a gap, and the value can come from another resource, known only after apply:

  ```hcl
  "app" = {
    A = [
      { content = aws_instance.web.public_ip, key = "web" }, # record key "app A web"
    ]
  }
  ```

  Give a `key` to every record whose value changes: addresses of servers, tokens, DKIM keys. With `require_keys = ["A", "AAAA", "TXT"]`, a record of these types without a `key` fails at `plan`.
- **Aliases**: `ALIASES` create CNAMEs that point to the name of the block.

Everything else (all record types, defaults, import of existing records, validation) builds on this; see the [full example](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/examples.md#full-example) and the [documentation](#documentation).

## Quick Start

1. Create an API token for the zone with the permission Zone, DNS, Edit (see [Requirements](#requirements)), and find the zone ID on the overview page of the zone in the Cloudflare dashboard.
2. Write the configuration, for example `main.tf`:

   ```hcl
   terraform {
     required_providers {
       cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.26" }
     }
   }

   # The token comes from the CLOUDFLARE_API_TOKEN environment variable
   provider "cloudflare" {}

   variable "zone_id" {
     type = string
   }

   module "dns" {
     source  = "5xxeu/ezdns/cloudflare"
     version = "2.18.0"

     zone_id   = var.zone_id
     zone_name = "example.com"

     records = {
       "@" = {
         A       = [{ key = "web", content = "192.0.2.10", proxied = true }]
         ALIASES = [{ content = "www", proxied = true }]
       }
     }
   }
   ```
3. Plan and apply:

   ```sh
   export CLOUDFLARE_API_TOKEN=...       # the token of step 1
   export TF_VAR_zone_id=023e105f4ecef8ad9ca31a8372d0c353
   terraform init
   terraform plan -out=tfplan            # shows one resource per record
   terraform apply tfplan
   ```

When the zone already has records, adopt them instead of creating them again: see [Importing Existing Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records), which also writes the configuration of an existing zone. More setups (mail, websites, CAA, several teams) are in the [examples](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/examples.md).

## Documentation

| Guide | What it covers |
|:------|:---------------|
| [Record Model](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/record-model.md#record-model) | Record types and their fields, nested names and aliases, record keys and when to set a `key`, changing values without a gap, values changed outside Terraform |
| [Validation](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/validation.md#validation) | What fails at `plan`, and what is left to the Cloudflare API |
| [Inputs and Outputs](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/reference.md#inputs-and-outputs) | The inputs, the fields of a record, defaults, comments and tags, the outputs |
| [Records in YAML](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/yaml.md#records-in-yaml) | Records in a YAML file with editor support, and records in several files (`record_groups`) |
| [Examples](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/examples.md) | A full example, and module calls for mail (Google Workspace, Microsoft 365), websites (GitHub Pages, Netlify, Vercel), CAA, SRV, HTTPS records, several teams in one zone, moving a server, next to external-dns and cert-manager |
| [Importing Existing Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records) | Adopting the records of an existing zone, and writing its configuration with `tools/zone-to-ezdns.py` |
| [Records Not in the Configuration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration) | Reporting records the configuration does not describe, and the part of the zone a module call owns |
| [Checking Plans Before Apply](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply) | `tools/plan-guard.py` in CI: deletions, replacements, proxy changes and required records |
| [Recipes](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#recipes) | Record types and fields the module does not support, records next to external-dns, Cloudflare Tunnel, a table of the zone for a wiki, internationalized names |
| [Module Sources](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/sources.md#module-sources) | A copy of the module from a release archive, and a Git source |
| [Testing](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing) | How the module is tested, and how to test your own records without credentials |
| [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration) | Notes for each release that can fail a plan that passed before, from v1 to v2, from provider v4 to v5 |
| [Troubleshooting](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/troubleshooting.md) | The common errors and warnings, why they happen and what to do |

## Features

- 📂 **Structured Schema**: Group records by their base name (subdomain or `@` for the zone apex).
- 🔗 **Smart Aliases**: Automatically create `CNAME` records pointing to your main records using the `ALIASES` key.
- 🛠 **Hybrid Names**: Support for nested subdomains like `_acme-challenge.app`.
- ☁️ **Cloudflare Optimized**: Automatic `TTL = 1` for proxied records.
- 🛡 **CAA Support**: Proper handling of CAA tags, flags, and values.
- 📥 **Import of Existing Records**: Adopt records that already exist in the zone with a single `import` block (provider v5).
- 🧩 **Structured Records**: `SRV`, `URI`, `HTTPS`, `SVCB`, `TLSA`, `SSHFP`, `DS`, `LOC` and other structured records through a single `data` map; see [Record Types](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/record-model.md#record-types) for the supported list.
- 🔀 **Provider v4 and v5**: The same input schema for both major versions of the Cloudflare provider.
- ✅ **Input Validation**: Mistakes in record types, names, IP addresses, TTL, MX or CAA fields and ranges of `data` fields (ports, priorities, LOC coordinates) fail at `plan`, before reaching the Cloudflare API.
- 🔓 **Values Changed Outside Terraform**: `ignore_changes` on a record keeps a value that a DDNS client or a change in the dashboard writes (provider v5).
- 🏷 **Defaults, Comments and Tags**: Set the TTL, proxying, comment and tags once for all records, and override them per record.
- 🗂 **Records in Several Files**: `record_groups` merge files of records (one per team or service) with defaults of their own, and a record defined twice fails instead of being overwritten.
- 🚧 **Boundaries in Shared Zones**: `owned_names` keeps a module call to its part of the zone, and the report of unmanaged records can ignore the records of other tools or stop the plan.
- 🔍 **Plan Checks and Zone Adoption**: Scripts that stop a plan which deletes, replaces or unproxies records, and that write the configuration of an existing zone.
- 🌍 **Internationalized Names**: The `idna` submodule takes zones, names and targets in Unicode (`münchen.de`) and converts them to Punycode.
- 🧾 **Tests Without Credentials**: The `compile` submodule returns the records of a configuration without a provider, for `terraform test` of your own zone.
- ✍️ **Editor Support for YAML**: A JSON Schema for records kept in YAML, for completion and highlighting of mistakes before `plan`.
- 🧪 **Tested End to End**: Every record type, updates, import and the v4 to v5 migration are tested against a real Cloudflare zone.

## Guarantees and Limits

What the module guarantees (tested in CI, and against a real zone before each release):

- Within 2.x, record keys and therefore the addresses in the state stay the same (see [Stability](#stability)). A record with a `key` keeps its address when its value changes.
- The checks listed in [Validation](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/validation.md#validation) fail at `plan`; what they do not cover is left to the Cloudflare API, which fails at `apply`.
- The module creates, changes and deletes only the records in its state. Records of other tools are never deleted, also with `report_unmanaged`.
- With `import_existing`, a configured record is adopted only when exactly one record of the zone matches it; several matches stop the plan.
- With `owned_names`, a configured record outside the owned part of the zone fails at `plan`.

Best-effort checks, which help a review but do not replace it:

- [`report_unmanaged`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#what-the-report-sees) reads the zone, not the state, so a record added next to a record that the plan creates is reported one plan later.
- [`tools/plan-guard.py`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply) reads the plan, not the zone or the order of the apply; when it cannot rule out an exposed origin, it fails rather than passes.

Limits of Terraform and the Cloudflare API:

- Without a `key`, the value is part of the address: a new value deletes the old record and creates a new one, in no fixed order. A name rewritten in another form (`www` to `www.example.com`) gets a new address too (see [Record Keys](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/record-model.md#record-keys)).
- Lifecycle rules (`prevent_destroy`, `create_before_destroy`) cannot be set on the records inside a module.

Reviewing the plan, and applying the plan that was reviewed (`terraform apply tfplan`), stays with the user.

## When Not to Use It

The module fits zones whose records are written down and change through review. Something else fits better when:

- **Records come from other systems at run time** (service discovery, Kubernetes ingresses, an inventory): a controller such as external-dns (it can work [next to the module](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#next-to-external-dns)), or `cloudflare_dns_record` with `for_each` over that data. The module needs the records at `plan`, and every value computed by another resource needs a `key` (see [Record Keys](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/record-model.md#record-keys)).
- **The zone must match the configuration exactly**, with records that are not in it deleted: the module manages only its own records and leaves the rest of the zone alone; [import](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records) only adopts records that are in the configuration, and [`report_unmanaged`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration) lists the other records without deleting them. With `unmanaged_policy = "error"`, such records stop the plan, so CI can keep a zone free of them (a best-effort check, see [What the Report Sees](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#what-the-report-sees)), but deleting them stays a manual step.
- **Records need lifecycle rules** (`prevent_destroy`, `create_before_destroy`): Terraform does not let a configuration set them on the resources inside a module. Values changed outside Terraform are covered by [`ignore_changes`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/record-model.md#values-changed-outside-terraform) on the record. A [check of the saved plan](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply) stops deletions and replacements in CI instead, also when a whole module call is removed.
- **Records need a type or field the module does not support**: see [the recipe](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#a-record-type-or-field-the-module-does-not-support) for managing them next to the module call; when that is most of the zone, plain resources are simpler.

## Requirements

| Module | Terraform | Cloudflare provider |
|--------|-----------|---------------------|
| Root module | `>= 1.8.0` | `~> 5.26` |
| `modules/dns/v4` | `>= 1.8.0` | `~> 4.41` |
| `modules/dns/v5` | `>= 1.8.0` | `~> 5.26` |
| `modules/dns/idna` | `>= 1.8.0` | `~> 5.26`, and [`5xxeu/idna`](https://registry.terraform.io/providers/5xxeu/idna/latest) `~> 0.1` |
| `modules/dns/compile` | `>= 1.8.0` | none |

The API token of the provider needs these permissions for the zone (Cloudflare dashboard, My Profile, API Tokens, Create Token, Custom token):

| Permission | Needed for |
|------------|------------|
| Zone, DNS, Edit | creating, changing and deleting the records (it includes reading them, which `import_existing`, `report_unmanaged` and `ignore_changes` do) |
| Zone, Zone, Read | looking up the zone name when `zone_name` is not set, and the plan of the zone when `minimum_ttl = "auto"` |

Limit the token to the zones it manages (Zone Resources, Include, Specific zone). A token for `terraform plan` in pull requests can have DNS Read instead of Edit.

If `zone_name` is not set, the module looks up the zone by `zone_id`, so the API token needs the `Zone:Read` permission. An internationalized zone (`münchen.de`) must set `zone_name` in Punycode (`xn--mnchen-3ya.de`): Cloudflare returns the names of such zones in Unicode, which cannot be used for the fully qualified names, so the lookup fails at `plan` with what to set. The [`idna` submodule](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#internationalized-names) converts names, also the looked-up zone name, to Punycode.

> **`zone_name` must be the name of the zone that `zone_id` refers to** (a trailing dot, as in zone files, is ignored). Setting it skips the lookup (no `Zone:Read` needed), and the module cannot check it: a wrong `zone_name` makes alias targets and fully qualified names point into another domain. Leave it unset when the token can read zones.

The v4 wrapper is kept for existing configurations. Provider v4 no longer gets new features, so new configurations should use v5 (the root module), and the v4 wrapper may be removed in a future major version. See [Migrating from v4 to v5](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#from-provider-v4-to-v5).

## Usage

### Terraform Registry

The module is published as [`5xxeu/ezdns/cloudflare`](https://registry.terraform.io/modules/5xxeu/ezdns/cloudflare/latest):

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.18.0"
  # ...
}
```

For provider v4, use `source = "5xxeu/ezdns/cloudflare//modules/dns/v4"`. Pin an exact version: an upgrade may need steps of its own, see [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration).

### Local Copy and Git Source

A copy of the module in your repository (a release archive with a checksum and signed build provenance) needs neither GitHub nor the Terraform Registry on `terraform init`, and a Git source fetches a tag. Both give the same module and the same addresses in the state as the Registry, so a configuration can switch between them without changes in the plan; see [Module Sources](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/sources.md#module-sources).

### HCL or YAML

Records can be written directly in `records` or kept in a YAML file passed through `yamldecode`. The module validates both the same way at `plan`; only YAML gets completion and highlighting of mistakes in the editor, through the [JSON Schema](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/yaml.md#records-in-yaml):

| | Records in HCL | Records in YAML |
|:-|:-|:-|
| Completion and mistakes highlighted in the editor | no (Terraform provides none inside `records`) | yes, with the JSON Schema |
| Validation at `plan` (typos, types, IP addresses, `data` fields, ...) | yes | yes |

## Stability

The module follows [Semantic Versioning](https://semver.org/): within 2.x, record keys and therefore the addresses in the state stay the same, inputs and outputs are only added, and a change that can fail a plan that passed before is described in [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration) (stricter validation of values the API would reject anyway). Many 2.x releases were made in September and October 2026; the record keys have not changed since 2.0. Each release passes the tests on Terraform 1.8 and the latest version, the end-to-end test against a real Cloudflare zone, and a review before the merge; from 2.16.0 the release workflow publishes nothing unless CI and the end-to-end test passed on the tagged commit.

Pin `version` exactly (or to a minor version, `~> 2.18.0`) and read the [CHANGELOG](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/CHANGELOG.md) before upgrading. Renovate and Dependabot update Registry and Git sources; [release archives](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/sources.md#local-copy) are upgraded by hand.

## License
MIT
