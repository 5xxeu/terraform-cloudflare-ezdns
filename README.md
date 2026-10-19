# Cloudflare DNS Records Factory (Terraform Module)

[![Release](https://img.shields.io/github/v/release/5xxeu/terraform-cloudflare-ezdns)](https://github.com/5xxeu/terraform-cloudflare-ezdns/releases/latest) [![Terraform Registry](https://img.shields.io/terraform/module/dt/5xxeu/ezdns/cloudflare?label=terraform%20registry&logo=terraform)](https://registry.terraform.io/modules/5xxeu/ezdns/cloudflare/latest) [![CI](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/ci.yml/badge.svg)](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/ci.yml) [![End-to-end](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/e2e.yml/badge.svg)](https://github.com/5xxeu/terraform-cloudflare-ezdns/actions/workflows/e2e.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/LICENSE)

A flexible Terraform module to manage Cloudflare DNS records using a structured object-based approach. Instead of defining multiple record resources, you can define your entire DNS zone (or sub-sections of it) in a single hierarchical map.

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
  version = "2.16.3"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "app" = {
      # app.example.com
      A = [{ content = "192.0.2.10" }]

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
  # module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["www CNAME"] will be created

Plan: 3 to add, 0 to change, 0 to destroy.
```

Each record is an instance of `module.dns.module.v5.cloudflare_dns_record.record`, with these keys:

| Record | Key in the state |
|:-------|:-----------------|
| `app.example.com A 192.0.2.10` | `app A 192.0.2.10` |
| `_acme-challenge.app.example.com TXT "token"` | `_acme-challenge.app TXT acme` |
| `www.example.com CNAME app.example.com` | `www CNAME` |

- **Names**: `"app"` is the name within the zone (`"@"` for the apex). A prefix before the type (`"_acme-challenge.TXT"`) is added to the name.
- **Addresses**: a record is addressed by its content, so adding or removing records in a list leaves the others alone. A changed value is a new record (the old one is deleted, the new one created, in no fixed order). With `key`, the key takes the place of the value in the address: a new value is an update in place, without a gap, and the value can come from another resource, known only after apply:

  ```hcl
  "app" = {
    A = [
      { content = aws_instance.web.public_ip, key = "web" }, # record key "app A web"
    ]
  }
  ```

  Give a `key` to every record whose value changes: addresses of servers, tokens, DKIM keys.
- **Aliases**: `ALIASES` create CNAMEs that point to the name of the block.

Everything else (all record types, defaults, import of existing records, validation) builds on this; see the [full example](#full-example) and the sections below.

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
     version = "2.16.3"

     zone_id   = var.zone_id
     zone_name = "example.com"

     records = {
       "@" = {
         A       = [{ content = "192.0.2.10", proxied = true }]
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

## Contents

- [Quick Start](#quick-start), [Features](#features), [When Not to Use It](#when-not-to-use-it), [Structure](#structure), [Requirements](#requirements)
- [Usage](#usage): [Terraform Registry](#terraform-registry), [local copy](#local-copy), [Git source](#git-source), [HCL or YAML](#hcl-or-yaml), [records in several files](#records-in-several-files) and the [full example](#full-example)
- [Record Model](#record-model): [record types](#record-types), [aliases](#the-aliases-logic), [record keys](#record-keys), [changing values without a gap](#changing-values-without-a-gap), [values changed outside Terraform](#values-changed-outside-terraform)
- [Validation](#validation), [Inputs](#inputs), [Outputs](#outputs)
- [Records in YAML](#records-in-yaml) with editor support, [Recipes](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#recipes): [unsupported types and fields](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#a-record-type-or-field-the-module-does-not-support), [external-dns](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#next-to-external-dns), [Cloudflare Tunnel](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#cloudflare-tunnel), [a table for a wiki](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#a-table-of-the-zone-for-a-wiki), [internationalized names](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#internationalized-names)
- [Importing Existing Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records) and [writing the configuration of an existing zone](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#writing-the-configuration-of-an-existing-zone), [Records Not in the Configuration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration), [the part of the zone a module call owns](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#the-part-of-the-zone-a-module-call-owns)
- [Checking Plans Before Apply](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply)
- [Stability](#stability), [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration)
- [Testing](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing), [testing your records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing-your-records)
- [Troubleshooting](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/troubleshooting.md): the common errors and warnings and what to do; all guides are listed in [docs](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/README.md)
- [Examples](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/examples.md): mail (Google Workspace, Microsoft 365), websites (GitHub Pages, Netlify, Vercel), CAA, SRV, HTTPS records, several teams in one zone, moving a server, next to external-dns and cert-manager

## Features

- 📂 **Structured Schema**: Group records by their base name (subdomain or `@` for the zone apex).
- 🔗 **Smart Aliases**: Automatically create `CNAME` records pointing to your main records using the `ALIASES` key.
- 🛠 **Hybrid Names**: Support for nested subdomains like `_acme-challenge.app`.
- ☁️ **Cloudflare Optimized**: Automatic `TTL = 1` for proxied records.
- 🛡 **CAA Support**: Proper handling of CAA tags, flags, and values.
- 📥 **Import of Existing Records**: Adopt records that already exist in the zone with a single `import` block (provider v5).
- 🧩 **Structured Records**: `SRV`, `URI`, `HTTPS`, `SVCB`, `TLSA`, `SSHFP`, `DS`, `LOC` and other structured records through a single `data` map; see [Record Types](#record-types) for the supported list.
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

## When Not to Use It

The module fits zones whose records are written down and change through review. Something else fits better when:

- **Records come from other systems at run time** (service discovery, Kubernetes ingresses, an inventory): a controller such as external-dns (it can work [next to the module](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#next-to-external-dns)), or `cloudflare_dns_record` with `for_each` over that data. The module needs the records at `plan`, and every value computed by another resource needs a `key` (see [Record Keys](#record-keys)).
- **The zone must match the configuration exactly**, with records that are not in it deleted: the module manages only its own records and leaves the rest of the zone alone; [import](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records) only adopts records that are in the configuration, and [`report_unmanaged`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration) lists the other records without deleting them. With `unmanaged_policy = "error"`, such records stop the plan, so CI can enforce a zone without them, but deleting them stays a manual step.
- **Records need lifecycle rules** (`prevent_destroy`, `create_before_destroy`): Terraform does not let a configuration set them on the resources inside a module. Values changed outside Terraform are covered by [`ignore_changes`](#values-changed-outside-terraform) on the record. A [check of the saved plan](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply) stops deletions and replacements in CI instead, also when a whole module call is removed.
- **Records need a type or field the module does not support**: see [the recipe](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#a-record-type-or-field-the-module-does-not-support) for managing them next to the module call; when that is most of the zone, plain resources are simpler.

## Structure

```
*.tf           # Root module: the v5 wrapper
modules/dns/
├── records/   # Provider-agnostic core: validation and flattening (internal)
├── compile/   # The checks of the wrappers without a provider, for tests of your records
├── idna/      # The v5 wrapper for names in Unicode, converted with the 5xxeu/idna provider
├── v4/        # Wrapper for Cloudflare provider v4 (cloudflare_record)
└── v5/        # Wrapper for Cloudflare provider v5 (cloudflare_dns_record);
               # migrate-from-v4.tf moves the state of the v4 wrapper
examples/
├── v5/        # Records in HCL
├── yaml/      # Records in a YAML file, validated by the JSON Schema
├── import/    # Adopting a zone that already has records
└── v4/        # Provider v4, for existing configurations
schema/        # JSON Schema for records in YAML
tools/         # plan-guard.py (checks a saved plan), moved-blocks.py (moved blocks from a plan), zone-to-ezdns.py (YAML of a zone)
```

Both wrappers share the same inputs, outputs and record keys, so switching between them only requires changing the `source`. The root module passes everything to the v5 wrapper, so it has the same inputs and outputs.

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

Use the module from the Terraform Registry, keep a copy of it in your configuration, or use it from Git. All three give the same module and the same addresses in the state, so a configuration can switch between them without changes in the plan.

### Terraform Registry

The module is published as [`5xxeu/ezdns/cloudflare`](https://registry.terraform.io/modules/5xxeu/ezdns/cloudflare/latest):

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.3"
  # ...
}
```

For provider v4, use `source = "5xxeu/ezdns/cloudflare//modules/dns/v4"`. Pin an exact version: an upgrade may need steps of its own, see [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration).

### Local Copy

A copy in your repository needs neither GitHub nor the Terraform Registry to get the module, and every change of the module shows up in your own history. Each [release](https://github.com/5xxeu/terraform-cloudflare-ezdns/releases) (up to 2.12.0, in the [previous repository](https://github.com/i386dev/terraform-cloudflare-easy-dns/releases), with archives named `terraform-cloudflare-easy-dns-*`) has an archive of the module with a checksum:

```sh
REPO=https://github.com/5xxeu/terraform-cloudflare-ezdns
VERSION=v2.16.3
ARCHIVE="terraform-cloudflare-ezdns-${VERSION}.tar.gz"
curl -fsSL -O "${REPO}/releases/download/${VERSION}/${ARCHIVE}"
curl -fsSL -O "${REPO}/releases/download/${VERSION}/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS   # macOS: shasum -a 256 --check
# Optional: the archive was built by the release workflow of this repository (releases up to 2.12.0: see SECURITY.md)
gh attestation verify "${ARCHIVE}" --repo 5xxeu/terraform-cloudflare-ezdns \
  --signer-workflow 5xxeu/terraform-cloudflare-ezdns/.github/workflows/release.yml
mkdir -p modules/ezdns
tar -xzf "${ARCHIVE}" -C modules/ezdns
```

Commit `modules/ezdns` together with your configuration and use it as a local module:

| Cloudflare provider | `source` |
|:--------------------|:---------|
| v5 | `./modules/ezdns` |
| v4 | `./modules/ezdns/modules/dns/v4` |

Keep the directory together: the wrappers use the shared core module through a relative path. The Cloudflare provider is still installed from the Terraform Registry on `terraform init`; for fully offline use, set up a provider mirror with `terraform providers mirror`. `modules/ezdns/VERSION` shows the version of the copy; to upgrade, replace the directory with the archive of the new version and follow [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration).

#### In a Larger Repository

Each release also has a provider v5 archive, `terraform-cloudflare-ezdns-v5-<version>.tar.gz` (in the same `SHA256SUMS`): the root module, `modules/dns/v5` and `modules/dns/records`, without the v4 wrapper and without `migrate-from-v4.tf`, the `moved` block for configurations that used the v4 wrapper. It is meant for repositories that pin provider v5 and run tools over every directory, where the v4 wrapper's `~> 4.41` would conflict. Updating such a copy is a plain replacement of the directory.

What a copy may change without affecting the module:

- `versions.tf` (root and `modules/dns/v5`) may be replaced by the repository's own pin, as long as it allows Terraform `>= 1.8.0` and the Cloudflare provider `>= 5.26` within v5
- `schema/` is only needed for records in YAML, and the `README.md` files of the submodules are generated reference
- With the full archive and no history on provider v4: `modules/dns/v4` and `modules/dns/v5/migrate-from-v4.tf` may be dropped, which gives the v5 archive

### Git Source

To fetch the module on `terraform init` instead, use a Git source with a tag (or the URL of your own mirror):

```hcl
source = "git::https://github.com/5xxeu/terraform-cloudflare-ezdns.git?ref=v2.16.3"
```

For provider v4, add `//modules/dns/v4` before `?ref=`. In CI, where every run starts from a clean checkout, add `&depth=1` after the tag (`?ref=v2.16.3&depth=1`) to fetch only that commit instead of the whole history.

### HCL or YAML

Records can be written directly in `records` or kept in a YAML file passed through `yamldecode`. The module validates both the same way at `plan`; only YAML gets completion and highlighting of mistakes in the editor, through the [JSON Schema](#records-in-yaml):

| | Records in HCL | Records in YAML |
|:-|:-|:-|
| Completion and mistakes highlighted in the editor | no (Terraform provides none inside `records`) | yes, with the JSON Schema |
| Validation at `plan` (typos, types, IP addresses, `data` fields, ...) | yes | yes |

### Records in Several Files

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
  version = "2.16.3"

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
- The group name is not a part of the [record keys](#record-keys): moving a record from one group to another, or between a group and `records`, keeps it in the state. Changing a group default changes the records of the group in place.
- `records` can be left out when every record is in a group. The checks of the module (CNAME conflicts, duplicates in different name forms, ...) see all records together.

### Full Example

A zone with most of the features: the apex, nested names, aliases, CAA and a structured SRV record.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.16.3"

  zone_id   = var.zone_id
  zone_name = "example.com" # optional, looked up from zone_id when omitted

  records = {
    # Zone apex (example.com)
    "@" = {
      A = [
        { content = "192.0.2.1", proxied = true },
      ]
      # Result: TXT record for _dmarc.example.com
      "_dmarc.TXT" = [
        { content = "v=DMARC1; p=none" },
      ]
      # An explicit key keeps the record in place when the value changes
      "google._domainkey.TXT" = [
        { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
      ]
      # Result: www.example.com -> CNAME -> example.com
      ALIASES = [
        { content = "www", proxied = true },
      ]
    }

    # This will manage records for app.example.com
    "app" = {
      A = [
        { content = "192.0.2.10", proxied = true },
      ]
      # Aliases create CNAMEs pointing to 'app.example.com'
      # Result: support.example.com -> CNAME -> app.example.com
      ALIASES = [
        { content = "support", ttl = 1800 },
      ]
      TXT = [
        { content = "v=spf1 include:_spf.google.com ~all" },
      ]
      MX = [
        { content = "mail.example.com", priority = 10 },
      ]
      CAA = [
        { content = "letsencrypt.org", tag = "issue" },
        { content = "letsencrypt.org", tag = "issuewild" },
      ]
      # Supports specific sub-keys.
      # Result: TXT record for _acme-challenge.app.example.com
      "_acme-challenge.TXT" = [
        { content = "verification-token" },
      ]
      # Inline aliases point to a prefixed name.
      # Result: static.example.com -> CNAME -> cdn.app.example.com
      "cdn.ALIASES" = [
        { content = "static" },
      ]
    }

    # Structured records use data instead of content
    # Result: SRV record for _sip._tcp.example.com
    "_sip._tcp" = {
      SRV = [{
        data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
      }]
    }
  }
}
```

The module creates these records:

<!-- BEGIN_RECORDS -->

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | A | `192.0.2.1` | 1 (auto) | `@ A 192.0.2.1` |
| `_acme-challenge.app.example.com` | TXT | `verification-token` | 3600 | `_acme-challenge.app TXT 2275f8d2b37d` |
| `_dmarc.example.com` | TXT | `v=DMARC1; p=none` | 3600 | `_dmarc TXT 21541c4e7044` |
| `_sip._tcp.example.com` | SRV | `10 5 5060 sip.example.com` | 3600 | `_sip._tcp SRV 9c61601f99e8` |
| `app.example.com` | A | `192.0.2.10` | 1 (auto) | `app A 192.0.2.10` |
| `app.example.com` | CAA | `issue letsencrypt.org` | 3600 | `app CAA issue letsencrypt.org` |
| `app.example.com` | CAA | `issuewild letsencrypt.org` | 3600 | `app CAA issuewild letsencrypt.org` |
| `app.example.com` | MX | `mail.example.com` (priority 10) | 3600 | `app MX mail.example.com` |
| `app.example.com` | TXT | `v=spf1 include:_spf.google.com ~all` | 3600 | `app TXT 585509e95a34` |
| `google._domainkey.example.com` | TXT | `v=DKIM1; k=rsa; p=MIIBIjANBg...` | 3600 | `google._domainkey TXT dkim` |
| `static.example.com` | CNAME | `cdn.app.example.com` | 3600 | `static CNAME` |
| `support.example.com` | CNAME | `app.example.com` | 1800 | `support CNAME` |
| `www.example.com` | CNAME | `example.com` | 1 (auto) | `www CNAME` |

<!-- END_RECORDS -->

More module calls for common setups (mail, websites, CAA, SRV, teams) are in [docs/examples.md](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/examples.md). Complete runnable configurations are available in [`examples`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/examples): `v5` (records in HCL), `yaml` (records in a YAML file), `import` (adopting an existing zone) and `v4` (provider v4, for existing configurations).

## Record Model

The module flattens the input map into a single map with a unique key for each record, which is then used in `for_each`.

### Record Types and Nested Names
Each key inside a base name block is a record type (`A`, `AAAA`, `CNAME`, `TXT`, `MX`, `CAA`, `SRV`, ...; see [Record Types](#record-types)). A key with a dot-notation (like `"_acme-challenge.TXT"`) is split: the last part is the record type, everything before it is prepended to the base name. Inside the `@` block the prefix becomes the record name itself (`"_dmarc.TXT"` becomes `_dmarc.example.com`).

### Record Types

Most records are defined by `content`. Structured records are defined by a `data` map instead, with the same fields as in the Cloudflare API. The module only checks which fields are present; what the fields and their values mean is described in the Cloudflare [DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/) and in the `data` attribute of [`cloudflare_dns_record`](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record), as are `settings`:

| Type | Defined by | `data` fields (optional in italics) |
|------|-----------|--------------------------------------|
| `A`, `AAAA`, `CNAME`, `NS`, `PTR`, `TXT` | `content` | - |
| `MX` | `content`, `priority` | - |
| `OPENPGPKEY` | `content` | - (provider v5 only) |
| `CAA` | `content`, `tag`, `flags` | - |
| `SRV` | `data` | `priority`, `weight`, `port`, `target` |
| `URI` | `data`, `priority` | `weight`, `target` |
| `HTTPS`, `SVCB` | `data` | `priority`, `target`, *`value`*, or service parameters instead of `value`: *`mandatory`*, *`alpn`*, *`port`*, *`ipv4hint`*, *`ech`*, *`ipv6hint`* |
| `TLSA`, `SMIMEA` | `data` | `usage`, `selector`, `matching_type`, `certificate` |
| `SSHFP` | `data` | `algorithm`, `type`, `fingerprint` |
| `DS` | `data` | `key_tag`, `algorithm`, `digest_type`, `digest` |
| `DNSKEY` | `data` | `flags`, `protocol`, `algorithm`, `public_key` |
| `CERT` | `data` | `type`, `key_tag`, `algorithm`, `certificate` |
| `NAPTR` | `data` | `order`, `preference`, `replacement`, *`flags`*, *`service`*, *`regex`* |
| `LOC` | `data` | `lat_degrees`, `lat_minutes`, `lat_seconds`, `lat_direction`, `long_degrees`, `long_minutes`, `long_seconds`, `long_direction`, *`altitude`*, *`size`*, *`precision_horz`*, *`precision_vert`* |

Service parameters of `HTTPS` and `SVCB` records (RFC 9460) can be written as text in `value` (`alpn="h3,h2" port="443"`) or as fields of `data`, which the module writes into `value` in the order of their keys, each in quotes: lists such as `alpn`, `mandatory`, `ipv4hint` and `ipv6hint` are comma-separated, `ech` is base64. A record uses one form or the other, not both. The fields are checked at `plan` (addresses in the hints, protocol IDs without spaces, `port` from 0 to 65535). The record key is the hash of `data` as written, so switching an existing record from `value` to fields gives it a new key: set a `key` first, or move it with a `moved` block.

```hcl
"@" = {
  HTTPS = [{
    key  = "web"
    data = { priority = 1, target = ".", alpn = "h3,h2", ipv4hint = "192.0.2.1" }
    # value = alpn="h3,h2" ipv4hint="192.0.2.1"
  }]
}
```

The service and protocol of `SRV`, `URI` and `TLSA` records are part of the name:

```hcl
"_sip._tcp" = {
  SRV = [{
    data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
  }]
}
"mail" = {
  "_25._tcp.TLSA" = [{
    key  = "mx"
    data = { usage = 3, selector = 1, matching_type = 1, certificate = "..." }
  }]
}
```

### The `ALIASES` Logic
When you define `ALIASES` inside a block (e.g., inside `"app"`), the module creates a `CNAME` record for each entry where:
- **Name**: The value provided in `content` (e.g., `support` for support.example.com).
- **Target**: The base name plus the zone domain (e.g., `app.example.com`, or `example.com` for `@`).

A base name may be short (`app`) or fully qualified (`app.example.com`): the target is the same fully qualified name, and `@` or the zone name point to the zone apex.

### Inline Aliases
A key like `"cdn.ALIASES"` works the same way, but the target is the prefixed name: `cdn.app.example.com` (or `cdn.example.com` for `@`).

### Record Keys
Each record is keyed in the state by its content, in the zone file format `<name> <TYPE> <value>`, so adding, removing or reordering items in a list affects only those items:

| Record | Key |
|--------|-----|
| `A`, `AAAA`, `MX`, `NS`, `PTR` | `app A 192.0.2.10`, `@ MX mail.example.com` |
| `TXT` | `_dmarc TXT 21541c4e7044` (first 12 characters of the SHA-1 of the value) |
| Records with `data` (`SRV`, `TLSA`, ...) | `_sip._tcp SRV 9c61601f99e8` (first 12 characters of the SHA-1 of the data) |
| `CNAME` and `ALIASES` | `www CNAME` (only one CNAME is allowed per name) |
| `CAA` | `app CAA issue letsencrypt.org` |
| Any record with `key` | `google._domainkey TXT dkim` |

```
module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"]
```

With the `v5` submodule the address is `module.dns.cloudflare_dns_record.record[...]`, with the `v4` submodule `module.dns.cloudflare_record.record[...]`.

Since the value is a part of the key, changing it replaces the record. For values that change over time (e.g. DKIM rotation or a server IP), set an explicit `key`, so the record is updated in place:

```hcl
"google._domainkey.TXT" = [
  { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
]
```

#### When to Use `key`

Use a `key` whenever the value of a record is expected to change, or is not known until `apply`:

- DKIM keys and other rotated values
- ACME challenge tokens and service verification records
- server IPs that change, e.g. after a migration
- values from other resources (`content = aws_instance.web.public_ip`)
- `MX` records that differ only in priority, `CAA` records that differ only in flags

Without a `key`, a changed value is a new record: the old one is deleted and the new one created.

**Values computed by other resources need a `key`.** `for_each` keys must be known at `plan`, so a record whose value comes from another resource (`content = aws_instance.web.public_ip`) fails with "The "for_each" value depends on resource attributes that cannot be determined until apply" unless it has a `key`:

```hcl
"web" = {
  A = [
    { content = aws_instance.web.public_ip, key = "web" }, # record key "web A web"
  ]
}
```

Two records that produce the same key (e.g. the same value listed twice, or a `CNAME` and an alias with the same name) fail at `plan` with the list of duplicates and where each of them is defined. `MX` records that differ only in `priority` and `CAA` records that differ only in `flags` get the same key too, since neither is a part of it; give each of them a `key`:

```hcl
MX = [
  { content = "mx.example.net", priority = 10, key = "primary" },
  { content = "mx.example.net", priority = 20, key = "backup" },
]
```

A `key` does not make a copy of a record a new one: two records with the same name, type and value (and priority, for `MX` and `URI`) fail at `plan` whatever their keys, since Cloudflare rejects identical records at `apply`.

Names are sent to Cloudflare in lower case, as Cloudflare stores them; the key keeps the name as written (`M1._domainkey TXT dkim`).

**Rewriting a name in another form changes its key.** `www`, `WWW` and `www.example.com` are the same DNS name, but the key keeps the form as written, so changing it (`www` to `www.example.com`, or `WWW` to `www`) gives the record a new address, and Terraform plans to delete and create it. The two are different instances, so their order is not fixed: when the delete goes first, the name does not answer until the create, and resolvers cache the empty answer for the negative TTL of the zone; when the create goes first, Cloudflare may reject it as a copy of the record that still exists, and the apply fails. To keep the existing record, add a `moved` block with the old and the new key, then check that the plan neither deletes nor creates it:

```hcl
moved {
  from = module.dns.module.v5.cloudflare_dns_record.record["www A 192.0.2.10"]
  to   = module.dns.module.v5.cloudflare_dns_record.record["www.example.com A 192.0.2.10"]
}
```

With the `//modules/dns/v5` submodule, the address has no `module.v5`; with the v4 wrapper, the resource is `cloudflare_record.record`.

`tools/moved-blocks.py` writes these blocks from a saved plan: it pairs each record that the plan deletes with the created record that is the same DNS record (zone, fully qualified name, type and value; TTL, proxy status, comment and tags change in place after the move). Copies of one record and values known only after apply are listed as comments to pair by hand (exit status 1):

```console
$ terraform plan -out=tfplan && terraform show -json tfplan > tfplan.json
$ python3 tools/moved-blocks.py tfplan.json --zone example.com > moved.tf
```

Check the blocks, apply, and remove them once every state that uses the module is applied.

### Changing Values Without a Gap

A changed value without a `key` gives the record a new key, so Terraform deletes the old record and creates the new one. Between the two, resolvers can get an empty answer and cache it for the negative TTL of the zone (the minimum of its SOA record). `create_before_destroy` does not change this: the old and the new record are different instances, and the option only orders the replacement of one instance. Two ways avoid the gap:

- **Update in place.** Give the record a `key` (see [When to Use `key`](#when-to-use-key)): the value changes on the same record, which answers with the old or the new value, never with none. The plan shows the difference:

  ```text
  # without a key: two resources, a gap between them
    # module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"] will be destroyed
    # module.dns.module.v5.cloudflare_dns_record.record["app A 198.51.100.10"] will be created

  # with key = "web": one resource, changed in place
    # module.dns.module.v5.cloudflare_dns_record.record["app A web"] will be updated in place
  ```
- **Overlap in steps**, when old and new values should both answer for a while, or when the record type changes. For a server move:

  1. Lower the TTL of the record (e.g. to 300) and apply. Wait for the old TTL to expire, so that resolvers have the short one.
  2. Add the new address next to the old one, each with a `key` (`old`, `new`), and apply. Clients now get both addresses.
  3. Check the new server, then remove the `old` record and apply.
  4. Restore the TTL.

  ```hcl
  "app" = {
    A = [
      { key = "old", content = "192.0.2.10", ttl = 300 },
      { key = "new", content = "198.51.100.10", ttl = 300 },
    ]
  }
  ```

  DKIM keys rotate the same way with a second selector: publish `s2._domainkey` next to `s1._domainkey`, switch the sender to `s2`, and remove `s1` after the messages signed with it have been delivered.

The same holds for proxied records: Cloudflare answers for them with its own addresses, but only while the record exists, so a changed origin address needs a `key` too. A type change on one name (an `A` record to a `CNAME`) cannot overlap: a CNAME cannot share its name with other records, so it is a delete and a create, in two applies or in one. A [check of the saved plan](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply) shows every replacement and deletion before it is applied.

### Values Changed Outside Terraform

A record whose value something else changes (a DDNS client that updates an address, a client that writes a token into an existing record, a proxy switched off in the dashboard during an incident) would be changed back by every apply. `ignore_changes` on the record lists the attributes that come from the record in the zone instead of the configuration, so a change made outside Terraform plans no change (provider v5):

```hcl
records = {
  "home" = {
    A = [{ key = "ddns", content = "192.0.2.1", ttl = 60, ignore_changes = ["content"] }]
  }
  "_acme-challenge" = {
    TXT = [{ key = "token", content = "pending", ignore_changes = ["content"] }]
  }
}
```

A client that creates and deletes records of its own (cert-manager and most ACME clients create a challenge record and delete it afterwards) needs no `ignore_changes`: leave its records out of `records`, and out of the report with [`unmanaged_ignore`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/examples.md#next-to-external-dns-and-cert-manager). `ignore_changes` is for a record that the module creates and something else updates.

The attributes are `content` (with `data` for structured records), `ttl`, `proxied`, `comment` and `tags`. The module still creates and deletes the record, and the attributes not listed stay managed. Terraform allows only literal values in `lifecycle`, so this is not `lifecycle { ignore_changes }`: the module reads the record from the zone at every `plan` (one lookup by name per such record, or within the lookup of its type that `import_existing` or `report_unmanaged` make anyway; DNS Read is enough) and sends the values it finds, so the plan has nothing to change. How it works out:

- **The record in the zone is found by name and type.** Cloudflare does not know the record key, and the configuration cannot read the ID in the state. So that it stays the same record whatever else changes, a record with `ignore_changes` is the only configured record of its type on its name (other `TXT` records go on another name, an `MX` with `ignore_changes` is the only `MX` of its name), and the zone may have at most one record of that name and type: otherwise the plan stops and lists them. A changed priority of an `MX` or `URI` record keeps the record.
- **A record not in the zone yet is created with the configured values**, and so is a record deleted outside Terraform: the configured value is the starting value.
- **A record that already exists** (created by the DDNS client before the module call) is adopted with `import_existing`, whatever its value, and [`report_unmanaged`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration) does not list it.
- **Changing a listed attribute in the configuration has no effect** while the record exists. Remove it from `ignore_changes` to set it: the next plan writes the configured value.
- **Use a `key`**, as in the example: without one, the record key has the configured value, which is no longer the value of the record.
- **A zone created in the same apply** has no records to read at `plan`, so the values are known only after apply, as with `import_existing`.
- **Provider v4** has no lookup of the records of a zone: the v4 wrapper stops the plan for a record with `ignore_changes`. The [`compile` submodule](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing-your-records), which reads nothing, returns the configured values.

## Validation

The `records` input (and the records of `record_groups`) is validated before any API call. The module checks the structure, the ranges of numeric fields and invariants that hold for every zone; what values mean (which DNSKEY algorithms exist, whether a TLSA certificate matches) is left to the Cloudflare API:

- Record attributes must be known: a misspelled attribute such as `proxid = true` fails with `records["app"]["A"][0]: unknown attribute "proxid"` instead of being ignored, and the same for `settings`

- Supported record types: see [Record Types](#record-types), plus `ALIASES` (with an optional prefix, e.g. `"_acme-challenge.TXT"`)
- Records defined by `content` must have a non-empty `content`
- Structured records must have `data` with only the fields of their type and all required ones; other records must not set `data`
- Numeric fields of `data` must be numbers in the range of their DNS wire format: priorities, weights, ports, key tags, `order` and `preference` from 0 to 65535, TLSA, SMIMEA and SSHFP fields and algorithms from 0 to 255, LOC degrees, minutes and seconds within their limits (latitude up to 90, longitude up to 180), LOC `altitude`, `size` and precisions as in RFC 1876, and `lat_direction` `N` or `S`, `long_direction` `E` or `W`; CAA `flags` from 0 to 255
- Service parameters of `HTTPS` and `SVCB` records, see [Record Types](#record-types)
- `ttl` and `default_ttl` must be whole numbers: `1` (automatic) or between `minimum_ttl` and `86400`. `minimum_ttl` is `60` by default: Cloudflare accepts TTLs below 60 seconds only on Enterprise zones, where it can be set to `30`; `minimum_ttl = "auto"` takes it from the plan of the zone (`30` on Enterprise, `60` on the others; one more API call, which needs Zone, Zone, Read). A lower TTL, and a `default_ttl` below `minimum_ttl` even if no record uses it, fail at `plan` with what to change; proxied records always get `1`
- Only `A`, `AAAA`, `CNAME` and `ALIASES` records can be `proxied`
- `MX` and `URI` records require `priority`, a whole number from 0 to 65535
- `A` records need an IPv4 address and `AAAA` records an IPv6 address (sent in the canonical form, `2001:db8::1` for `2001:0DB8:0:0:0:0:0:1`, as Cloudflare stores it; the [key](#record-keys) keeps the address as written); `CNAME`, `MX`, `NS` and `PTR` records need a DNS name: labels of letters, digits, `_` and `-` (up to 63 characters) separated by dots, at most 253 characters, an optional trailing dot, and not an IP address (`@` stands for the zone apex and is sent as the zone name, and `.` is a null `MX`, RFC 7505, which must have `priority` 0)
- `target` of `SRV`, `HTTPS` and `SVCB` records and `replacement` of `NAPTR` records must be a DNS name by the same rule, or `.` (no service for `SRV`, the owner name for `HTTPS` and `SVCB`, no replacement for `NAPTR`). `@` is not accepted there: the module passes `data` to Cloudflare as written. `URI` targets are URIs and are not checked
- `TXT` values are limited to 2048 characters
- Names, prefixes and `ALIASES` must be valid DNS names: labels of letters, digits, `_` and `-` separated by dots. Internationalized names, also in `zone_name`, must be given in Punycode (`xn--mnchen-3ya` for `münchen`), as the Cloudflare API expects them ([Internationalized Names](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#internationalized-names) shows how to convert them)
- The fully qualified name of a record (prefix, name and zone together) can have at most 253 characters, and so can the target of a prefixed `ALIASES`
- A wildcard `*` must be the whole leftmost label, also in the names a prefix and a base name combine into (`"_acme-challenge.TXT"` under `"*"` would give `_acme-challenge.*`) and in the targets of `<prefix>.ALIASES`
- A `CNAME` or alias cannot point to its own name (case, a trailing dot, `@` and the short form do not matter)
- `CAA` records require `tag`: `issue`, `issuewild` or `iodef`
- `key` must be a non-empty string without whitespace
- Attributes that do not apply to the type of a record (`content` of a record with `data`, `priority` other than on `MX` and `URI`, `tag` and `flags` other than on `CAA`) show a warning, since the module ignores them; they will fail from 3.0
- Two different SPF records on one name, two DMARC records on a `_dmarc` name, and a null `MX` next to other `MX` records on one name (RFC 7505) show a warning: Cloudflare accepts them, but mail receivers do not, see [Troubleshooting](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/troubleshooting.md#a-name-with-a-null-mx-has-other-mx-records)
- With [`owned_names`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#the-part-of-the-zone-a-module-call-owns), every record must be in the part of the zone that the module call owns
- Record keys must be unique. The error shows where each duplicate is defined, e.g. `"_acme-challenge.app TXT 79bead8e6d65" from records["_acme-challenge.app"]["TXT"][0] and records["app"]["_acme-challenge.TXT"][0]`
- The same record must not be written twice in different forms, which would give it two keys: names in different forms (`www` and `www.example.com`, `@` and the zone name), and values that the [import](docs/importing.md#importing-existing-records) takes for one record (hostnames in any case and with or without a trailing dot, IPv6 addresses in another form, a TXT value quoted or not, numbers in `data` written differently, such as `5060` and `"5060.0"`). Records with a `key` are compared by their keys
- A `CNAME` (including `ALIASES`) cannot share its name with other records, except at the zone apex (`@` or the zone name) where Cloudflare uses CNAME flattening and only `A` and `AAAA` conflict with it, and a name has at most one `CNAME`, also with different `key`s. Names are compared fully qualified, so `www` and `www.example.com` are the same name
- **Migration escape hatch for legacy zones:** existing zones may have names where a `CNAME` shares its name with other records, which Cloudflare accepts for records that are not proxied. Such names can be listed in `allowed_cname_conflicts` (compared fully qualified and case-insensitively), so the zone can be adopted without changing live DNS first. Only the listed names are exempt: a conflict on any other name still fails, a second `CNAME` on a listed name still fails, and a listed name that has no conflict anymore shows a warning so the list can shrink:

  ```hcl
  allowed_cname_conflicts = ["community", "*.legacy"]
  ```

  The listed names must be valid names, written like the names in `records`.

A failed check stops the plan and lists every record that fails it, with where it is defined:

```text
Error: Invalid value for variable

Record data fields and CAA flags must be in range:
records["_sip._tcp"]["SRV"][0].data.port: "70000" (a whole number from 0 to
65535)
```

Attributes that the module ignores only show a warning in 2.x:

```text
Warning: Check block assertion failed

These attributes do not apply to the type of their record and are ignored
(SRV keeps its priority in data; content is for records without data; tag and
flags are for CAA). Remove them: from 3.0 they will fail the plan:
records["app"]["A"][0].priority
```

## Inputs

Both wrappers take `zone_id`, `zone_name` (optional, looked up from `zone_id` when omitted; when set, it must be the name of that zone, see [Requirements](#requirements)), `records`, [`record_groups`](#records-in-several-files), the [defaults](#defaults-comments-and-tags), `minimum_ttl`, `allowed_cname_conflicts` (see [Validation](#validation)) and [`owned_names`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#the-part-of-the-zone-a-module-call-owns); the v5 wrapper also takes `import_existing`, `report_unmanaged`, `unmanaged_ignore` and `unmanaged_policy`. The [`compile`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing-your-records) submodule takes the inputs of the v4 wrapper without `zone_id`, with `zone_name` required, and the [`idna`](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#internationalized-names) submodule the inputs of the root module, with names in Unicode.

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
| `data` | Fields of structured records, see [Record Types](#record-types) | `null` |
| `key` | Stable key used instead of the value in the record key, see [Record Keys](#record-keys) | `null` |
| `comment` | Note shown in the Cloudflare dashboard | `default_comment` |
| `tags` | Tags such as `owner:web`, added to `default_tags` | `[]` |
| `settings` | `flatten_cname`, `ipv4_only` and `ipv6_only` (provider v5 only, ignored by the v4 wrapper with a warning) | `null` |
| `private_routing` | Private network routing to the origin of an `A`, `AAAA` or `CNAME` record (provider v5 only, ignored by the v4 wrapper with a warning) | `null` |
| `ignore_changes` | Attributes taken from the record in the zone, for values changed outside Terraform: `content`, `ttl`, `proxied`, `comment`, `tags`; see [Values Changed Outside Terraform](#values-changed-outside-terraform) (provider v5 only) | `null` |

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
  version = "2.16.3"

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
- `records`: managed records keyed by their [record key](#record-keys), with `id`, `zone_id`, `name` (as Cloudflare returns it), `fqdn` (fully qualified and in lower case, from the configuration, so it is known at `plan`), `type`, `content`, `ttl`, `proxied`, `priority` and `data` (structured records, as configured). For other modules, e.g. monitoring of the names or certificates for them:

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
- `state_migration`: map of the record keys used by 1.x to the current ones, see [Upgrading from v1](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#from-v1-to-v2)
- `import_ids` (v5): import IDs of records that already exist in the zone, see [Importing Existing Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records)
- `import_duplicates` (v5): records that cannot be imported unambiguously, with the IDs of their matches; while there are any, `plan` stops
- `unmanaged_records` (v5): with `report_unmanaged`, the records of the zone that the configuration does not describe, see [Records Not in the Configuration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration)

## Records in YAML

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

`schema/records.schema.json` is a JSON Schema for such a file (a document with a `records` key). Editors use it for completion of record types, attributes and `data` fields, and highlight mistakes such as `proxid`, `ttl: 5m` or a CAA `tag` that does not exist before `terraform plan`. With a [local copy](#local-copy), the schema is at `modules/ezdns/schema/records.schema.json`.

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

Use the schema of the module version you use. For records written in HCL, there is no such completion (see [HCL or YAML](#hcl-or-yaml)); mistakes are reported at `plan`.

**Quote text values.** `yamldecode` follows YAML 1.1, where unquoted `yes`, `no`, `on`, `off`, `y` and `n` (in any case) are booleans and `0123` or `1.10` are numbers; Terraform would turn them into `"false"`, `"123"` or `"1.1"` without an error. The module rejects booleans in `content`, `key`, `comment`, `tag`, `tags` and the fields of `data`, and warns about numbers in them (in `data`, only in the text fields such as `target`, `value` or `digest`; `port` or `priority` may be numbers). The unquoted `N` of a LOC `lat_direction` is accepted. Quoted, values stay as written:

```yaml
TXT:
  - content: "off"     # not: content: off  ->  "false"
  - content: "0123"    # not: content: 0123 ->  "123"
```

## Recipes

Recipes for what the module does not do itself: [record types and fields it does not support](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#a-record-type-or-field-the-module-does-not-support), [records next to external-dns](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#next-to-external-dns) and [internationalized names](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/recipes.md#internationalized-names).

## Importing Existing Records

Existing records of a zone are adopted with `import_existing = true` (the plan then imports instead of creating them), and `tools/zone-to-ezdns.py` writes the configuration of an existing zone. See [Importing Existing Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#importing-existing-records) and [Writing the Configuration of an Existing Zone](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/importing.md#writing-the-configuration-of-an-existing-zone).

## Records Not in the Configuration

With `report_unmanaged = true`, the plan reports records of the zone that are not in the configuration (`unmanaged_ignore` leaves out expected ones, `unmanaged_policy = "error"` stops the plan), and `owned_names` limits a module call to its part of the zone. Nothing is deleted. See [Records Not in the Configuration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#records-not-in-the-configuration) and [The Part of the Zone a Module Call Owns](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/unmanaged-records.md#the-part-of-the-zone-a-module-call-owns).

## Checking Plans Before Apply

`tools/plan-guard.py` checks a saved plan in CI and fails when it deletes or replaces records, turns off the proxy of a record or leaves a required record set empty. See [Checking Plans Before Apply](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/plan-guard.md#checking-plans-before-apply).

## Stability

The module follows [Semantic Versioning](https://semver.org/): within 2.x, record keys and therefore the addresses in the state stay the same, inputs and outputs are only added, and a change that can fail a plan that passed before is described in [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration) (stricter validation of values the API would reject anyway). Many 2.x releases were made in September and October 2026; the record keys have not changed since 2.0. Each release passes the tests on Terraform 1.8 and the latest version, the end-to-end test against a real Cloudflare zone, and a review before the merge; from 2.16.0 the release workflow publishes nothing unless CI and the end-to-end test passed on the tagged commit.

Pin `version` exactly (or to a minor version, `~> 2.16.0`) and read the [CHANGELOG](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/CHANGELOG.md) before upgrading. Renovate and Dependabot update Registry and Git sources; [release archives](#local-copy) are upgraded by hand.

## Upgrading and Migration

Within 2.x, upgrades need no changes to the configuration or the state; a release that can fail a plan that passed before says so. See [Upgrading and Migration](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/upgrading.md#upgrading-and-migration) for each such release, from v1 to v2, from provider v4 to v5 and from earlier module addresses.

## Testing

The module is tested with `terraform test` against a mocked provider (no credentials) and end to end against a real Cloudflare zone; your own records can be tested the same way. See [Testing](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing) and [Testing Your Records](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/docs/testing.md#testing-your-records).

## License
MIT
