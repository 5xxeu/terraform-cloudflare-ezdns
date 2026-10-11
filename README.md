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
  version = "2.13.0"

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
- **Addresses**: a record is addressed by its content, so adding or removing records in a list leaves the others alone. With `key`, the value can change without replacing the record, e.g. for tokens or DKIM keys.
- **Aliases**: `ALIASES` create CNAMEs that point to the name of the block.

Everything else (all record types, defaults, import of existing records, validation) builds on this; see the [full example](#full-example) and the sections below.

## Contents

- [Features](#features), [When Not to Use It](#when-not-to-use-it), [Structure](#structure), [Requirements](#requirements)
- [Usage](#usage): [Terraform Registry](#terraform-registry), [local copy](#local-copy), [Git source](#git-source), [HCL or YAML](#hcl-or-yaml), [records in several files](#records-in-several-files) and the [full example](#full-example)
- [Record Model](#record-model): [record types](#record-types), [aliases](#the-aliases-logic), [record keys](#record-keys), [changing values without a gap](#changing-values-without-a-gap)
- [Validation](#validation), [Inputs](#inputs), [Outputs](#outputs)
- [Records in YAML](#records-in-yaml) with editor support, [Recipes](#recipes): [unsupported types and fields](#a-record-type-or-field-the-module-does-not-support), [external-dns](#next-to-external-dns), [internationalized names](#internationalized-names)
- [Importing Existing Records](#importing-existing-records) and [writing the configuration of an existing zone](#writing-the-configuration-of-an-existing-zone), [Records Not in the Configuration](#records-not-in-the-configuration), [the part of the zone a module call owns](#the-part-of-the-zone-a-module-call-owns)
- [Checking Plans Before Apply](#checking-plans-before-apply)
- [Stability](#stability), [Upgrading and Migration](#upgrading-and-migration)
- [Testing](#testing), [testing your records](#testing-your-records)

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

- **Records come from other systems at run time** (service discovery, Kubernetes ingresses, an inventory): a controller such as external-dns (it can work [next to the module](#next-to-external-dns)), or `cloudflare_dns_record` with `for_each` over that data. The module needs the records at `plan`, and every value computed by another resource needs a `key` (see [Record Keys](#record-keys)).
- **The zone must match the configuration exactly**, with records that are not in it deleted: the module manages only its own records and leaves the rest of the zone alone; [import](#importing-existing-records) only adopts records that are in the configuration, and [`report_unmanaged`](#records-not-in-the-configuration) lists the other records without deleting them. With `unmanaged_policy = "error"`, such records stop the plan, so CI can enforce a zone without them, but deleting them stays a manual step.
- **Records need lifecycle rules** (`prevent_destroy`, `ignore_changes`): Terraform does not let a configuration set them on the resources inside a module. A [check of the saved plan](#checking-plans-before-apply) stops deletions and replacements in CI instead, also when a whole module call is removed.
- **Records need a type or field the module does not support**: see [the recipe](#a-record-type-or-field-the-module-does-not-support) for managing them next to the module call; when that is most of the zone, plain resources are simpler.

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
tools/         # plan-guard.py (checks a saved plan), zone-to-ezdns.py (writes the YAML of a zone)
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

If `zone_name` is not set, the module looks up the zone by `zone_id`, so the API token needs the `Zone:Read` permission. An internationalized zone (`münchen.de`) must set `zone_name` in Punycode (`xn--mnchen-3ya.de`): Cloudflare returns the names of such zones in Unicode, which cannot be used for the fully qualified names, so the lookup fails at `plan` with what to set. The [`idna` submodule](#internationalized-names) converts names, also the looked-up zone name, to Punycode.

> **`zone_name` must be the name of the zone that `zone_id` refers to** (a trailing dot, as in zone files, is ignored). Setting it skips the lookup (no `Zone:Read` needed), and the module cannot check it: a wrong `zone_name` makes alias targets and fully qualified names point into another domain. Leave it unset when the token can read zones.

The v4 wrapper is kept for existing configurations. Provider v4 no longer gets new features, so new configurations should use v5 (the root module), and the v4 wrapper may be removed in a future major version. See [Migrating from v4 to v5](#from-provider-v4-to-v5).

## Usage

Use the module from the Terraform Registry, keep a copy of it in your configuration, or use it from Git. All three give the same module and the same addresses in the state, so a configuration can switch between them without changes in the plan.

### Terraform Registry

The module is published as [`5xxeu/ezdns/cloudflare`](https://registry.terraform.io/modules/5xxeu/ezdns/cloudflare/latest):

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.13.0"
  # ...
}
```

For provider v4, use `source = "5xxeu/ezdns/cloudflare//modules/dns/v4"`. Pin an exact version: an upgrade may need steps of its own, see [Upgrading and Migration](#upgrading-and-migration).

### Local Copy

A copy in your repository needs neither GitHub nor the Terraform Registry to get the module, and every change of the module shows up in your own history. Each [release](https://github.com/5xxeu/terraform-cloudflare-ezdns/releases) (up to 2.12.0, in the [previous repository](https://github.com/i386dev/terraform-cloudflare-easy-dns/releases), with archives named `terraform-cloudflare-easy-dns-*`) has an archive of the module with a checksum:

```sh
REPO=https://github.com/5xxeu/terraform-cloudflare-ezdns
VERSION=v2.13.0
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

Keep the directory together: the wrappers use the shared core module through a relative path. The Cloudflare provider is still installed from the Terraform Registry on `terraform init`; for fully offline use, set up a provider mirror with `terraform providers mirror`. `modules/ezdns/VERSION` shows the version of the copy; to upgrade, replace the directory with the archive of the new version and follow [Upgrading and Migration](#upgrading-and-migration).

#### In a Larger Repository

Each release also has a provider v5 archive, `terraform-cloudflare-ezdns-v5-<version>.tar.gz` (in the same `SHA256SUMS`): the root module, `modules/dns/v5` and `modules/dns/records`, without the v4 wrapper and without `migrate-from-v4.tf`, the `moved` block for configurations that used the v4 wrapper. It is meant for repositories that pin provider v5 and run tools over every directory, where the v4 wrapper's `~> 4.41` would conflict. Updating such a copy is a plain replacement of the directory.

What a copy may change without affecting the module:

- `versions.tf` (root and `modules/dns/v5`) may be replaced by the repository's own pin, as long as it allows Terraform `>= 1.8.0` and the Cloudflare provider `>= 5.26` within v5
- `schema/` is only needed for records in YAML, and the `README.md` files of the submodules are generated reference
- With the full archive and no history on provider v4: `modules/dns/v4` and `modules/dns/v5/migrate-from-v4.tf` may be dropped, which gives the v5 archive

### Git Source

To fetch the module on `terraform init` instead, use a Git source with a tag (or the URL of your own mirror):

```hcl
source = "git::https://github.com/5xxeu/terraform-cloudflare-ezdns.git?ref=v2.13.0"
```

For provider v4, add `//modules/dns/v4` before `?ref=`. In CI, where every run starts from a clean checkout, add `&depth=1` after the tag (`?ref=v2.13.0&depth=1`) to fetch only that commit instead of the whole history.

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
  version = "2.13.0"

  zone_id      = var.zone_id
  zone_name    = "example.com"
  default_tags = ["managed-by:terraform"]

  record_groups = {
    mail = {
      defaults = { comment = "mail", tags = ["team:mail"] }
      records  = yamldecode(file("${path.module}/mail.ezdns.yaml")).records
    }
    web = {
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
  version = "2.13.0"

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

| Name | Type | Value | TTL | Record key |
|:-----|:-----|:------|----:|:-----------|
| `example.com` | A | `192.0.2.1` | 1 | `@ A 192.0.2.1` |
| `_dmarc.example.com` | TXT | `v=DMARC1; p=none` | 3600 | `_dmarc TXT 21541c4e7044` |
| `google._domainkey.example.com` | TXT | `v=DKIM1; k=rsa; p=MIIBIjANBg...` | 3600 | `google._domainkey TXT dkim` |
| `www.example.com` | CNAME | `example.com` | 1 | `www CNAME` |
| `app.example.com` | A | `192.0.2.10` | 1 | `app A 192.0.2.10` |
| `support.example.com` | CNAME | `app.example.com` | 1800 | `support CNAME` |
| `app.example.com` | TXT | `v=spf1 include:_spf.google.com ~all` | 3600 | `app TXT 585509e95a34` |
| `app.example.com` | MX | `mail.example.com` (priority 10) | 3600 | `app MX mail.example.com` |
| `app.example.com` | CAA | `issue letsencrypt.org` | 3600 | `app CAA issue letsencrypt.org` |
| `app.example.com` | CAA | `issuewild letsencrypt.org` | 3600 | `app CAA issuewild letsencrypt.org` |
| `_acme-challenge.app.example.com` | TXT | `verification-token` | 3600 | `_acme-challenge.app TXT 2275f8d2b37d` |
| `static.example.com` | CNAME | `cdn.app.example.com` | 3600 | `static CNAME` |
| `_sip._tcp.example.com` | SRV | `10 5 5060 sip.example.com` | 3600 | `_sip._tcp SRV 9c61601f99e8` |

Complete runnable configurations are available in [`examples`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/examples): `v5` (records in HCL), `yaml` (records in a YAML file), `import` (adopting an existing zone) and `v4` (provider v4, for existing configurations).

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
  A = [{ key = "web", content = aws_instance.web.public_ip }]
}
```

Two records that produce the same key (e.g. the same value listed twice, or a `CNAME` and an alias with the same name) fail at `plan` with the list of duplicates and where each of them is defined. `MX` records that differ only in `priority` and `CAA` records that differ only in `flags` get the same key too, since neither is a part of it; give each of them a `key`:

```hcl
MX = [
  { content = "mx.example.net", priority = 10, key = "primary" },
  { content = "mx.example.net", priority = 20, key = "backup" },
]
```

Names are sent to Cloudflare in lower case, as Cloudflare stores them; the key keeps the name as written (`M1._domainkey TXT dkim`).

**Rewriting a name in another form changes its key.** `www`, `WWW` and `www.example.com` are the same DNS name, but the key keeps the form as written, so changing it (`www` to `www.example.com`, or `WWW` to `www`) gives the record a new address, and Terraform plans to delete and create it. To keep the existing record, add a `moved` block with the old and the new key, then check that the plan neither deletes nor creates it:

```hcl
moved {
  from = module.dns.module.v5.cloudflare_dns_record.record["www A 192.0.2.10"]
  to   = module.dns.module.v5.cloudflare_dns_record.record["www.example.com A 192.0.2.10"]
}
```

With the `//modules/dns/v5` submodule, the address has no `module.v5`; with the v4 wrapper, the resource is `cloudflare_record.record`.

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

The same holds for proxied records: Cloudflare answers for them with its own addresses, but only while the record exists, so a changed origin address needs a `key` too. A type change on one name (an `A` record to a `CNAME`) cannot overlap: a CNAME cannot share its name with other records, so it is a delete and a create, in two applies or in one. A [check of the saved plan](#checking-plans-before-apply) shows every replacement and deletion before it is applied.

## Validation

The `records` input (and the records of `record_groups`) is validated before any API call. The module checks the structure, the ranges of numeric fields and invariants that hold for every zone; what values mean (which DNSKEY algorithms exist, whether a TLSA certificate matches) is left to the Cloudflare API:

- Record attributes must be known: a misspelled attribute such as `proxid = true` fails with `records["app"]["A"][0]: unknown attribute "proxid"` instead of being ignored, and the same for `settings`

- Supported record types: see [Record Types](#record-types), plus `ALIASES` (with an optional prefix, e.g. `"_acme-challenge.TXT"`)
- Records defined by `content` must have a non-empty `content`
- Structured records must have `data` with only the fields of their type and all required ones; other records must not set `data`
- Numeric fields of `data` must be numbers in the range of their DNS wire format: priorities, weights, ports, key tags, `order` and `preference` from 0 to 65535, TLSA, SMIMEA and SSHFP fields and algorithms from 0 to 255, LOC degrees, minutes and seconds within their limits (latitude up to 90, longitude up to 180), LOC `altitude`, `size` and precisions as in RFC 1876, and `lat_direction` `N` or `S`, `long_direction` `E` or `W`; CAA `flags` from 0 to 255
- Service parameters of `HTTPS` and `SVCB` records, see [Record Types](#record-types)
- `ttl` and `default_ttl` must be whole numbers: `1` (automatic) or between `minimum_ttl` and `86400`. `minimum_ttl` is `60` by default: Cloudflare accepts TTLs below 60 seconds only on Enterprise zones, where it can be set to `30`. A lower TTL, and a `default_ttl` below `minimum_ttl` even if no record uses it, fail at `plan` with what to change; proxied records always get `1`
- Only `A`, `AAAA`, `CNAME` and `ALIASES` records can be `proxied`
- `MX` and `URI` records require `priority`, a whole number from 0 to 65535
- `A` records need an IPv4 address and `AAAA` records an IPv6 address (sent in the canonical form, `2001:db8::1` for `2001:0DB8:0:0:0:0:0:1`, as Cloudflare stores it; the [key](#record-keys) keeps the address as written); `CNAME`, `MX`, `NS` and `PTR` records need a DNS name: labels of letters, digits, `_` and `-` (up to 63 characters) separated by dots, at most 253 characters, an optional trailing dot, and not an IP address (`@` stands for the zone apex, and `.` is a null `MX`, RFC 7505, which must have `priority` 0)
- `target` of `SRV`, `HTTPS` and `SVCB` records and `replacement` of `NAPTR` records must be a DNS name by the same rule, or `.` (no service for `SRV`, the owner name for `HTTPS` and `SVCB`, no replacement for `NAPTR`). `@` is not accepted there: the module passes `data` to Cloudflare as written. `URI` targets are URIs and are not checked
- `TXT` values are limited to 2048 characters
- Names, prefixes and `ALIASES` must be valid DNS names: labels of letters, digits, `_` and `-` separated by dots. Internationalized names, also in `zone_name`, must be given in Punycode (`xn--mnchen-3ya` for `münchen`), as the Cloudflare API expects them ([Internationalized Names](#internationalized-names) shows how to convert them)
- The fully qualified name of a record (prefix, name and zone together) can have at most 253 characters, and so can the target of a prefixed `ALIASES`
- A wildcard `*` must be the whole leftmost label, also in the names a prefix and a base name combine into (`"_acme-challenge.TXT"` under `"*"` would give `_acme-challenge.*`) and in the targets of `<prefix>.ALIASES`
- A `CNAME` or alias cannot point to its own name (case, a trailing dot, `@` and the short form do not matter)
- `CAA` records require `tag`: `issue`, `issuewild` or `iodef`
- `key` must be a non-empty string without whitespace
- Attributes that do not apply to the type of a record (`content` of a record with `data`, `priority` other than on `MX` and `URI`, `tag` and `flags` other than on `CAA`) show a warning, since the module ignores them; they will fail from 3.0
- With [`owned_names`](#the-part-of-the-zone-a-module-call-owns), every record must be in the part of the zone that the module call owns
- Record keys must be unique. The error shows where each duplicate is defined, e.g. `"_acme-challenge.app TXT 79bead8e6d65" from records["_acme-challenge.app"]["TXT"][0] and records["app"]["_acme-challenge.TXT"][0]`
- The same record must not be written twice with different name forms (`www` and `www.example.com`, `@` and the zone name), which would give it two keys; addresses and hostnames (`A`, `AAAA`, `MX`, `NS`, `PTR`) are compared case-insensitively and without a trailing dot
- A `CNAME` (including `ALIASES`) cannot share its name with other records, except at the zone apex (`@` or the zone name) where Cloudflare uses CNAME flattening, and a name has at most one `CNAME`, also with different `key`s. Names are compared fully qualified, so `www` and `www.example.com` are the same name
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

Both wrappers take `zone_id`, `zone_name` (optional, looked up from `zone_id` when omitted; when set, it must be the name of that zone, see [Requirements](#requirements)), `records`, [`record_groups`](#records-in-several-files), the [defaults](#defaults-comments-and-tags), `minimum_ttl`, `allowed_cname_conflicts` (see [Validation](#validation)) and [`owned_names`](#the-part-of-the-zone-a-module-call-owns); the v5 wrapper also takes `import_existing`, `report_unmanaged`, `unmanaged_ignore` and `unmanaged_policy`. The [`compile`](#testing-your-records) submodule takes the inputs of the v4 wrapper without `zone_id`, with `zone_name` required, and the [`idna`](#internationalized-names) submodule the inputs of the root module, with names in Unicode.

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
| `settings` | `flatten_cname`, `ipv4_only` and `ipv6_only` (provider v5 only, ignored by the v4 wrapper) | `null` |

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
  version = "2.13.0"

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

- `record_names`: names of all managed records
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
- `state_migration`: map of the record keys used by 1.x to the current ones, see [Upgrading from v1](#from-v1-to-v2)
- `import_ids` (v5): import IDs of records that already exist in the zone, see [Importing Existing Records](#importing-existing-records)
- `import_duplicates` (v5): records that cannot be imported unambiguously, with the IDs of their matches; while there are any, `plan` stops
- `unmanaged_records` (v5): with `report_unmanaged`, the records of the zone that the configuration does not describe, see [Records Not in the Configuration](#records-not-in-the-configuration)

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

### A Record Type or Field the Module Does Not Support

Record types and attributes are a closed list, so misspelled ones fail at `plan`. When Cloudflare adds something the module does not know yet, manage that record with the provider resource next to the module call, in the same zone:

```hcl
resource "cloudflare_dns_record" "special" {
  zone_id = var.zone_id
  name    = "special"
  type    = "TXT"
  content = "..."
  ttl     = 1
  # any argument the provider supports
}
```

Keep it out of `records`, so the record is not managed twice. Once the module supports it, move it into `records` with a `moved` block to its key.

Mail with SPF, DKIM and DMARC; the DKIM record has a `key`, so rotating the key updates the record in place:

```hcl
"@" = {
  MX = [
    { content = "mx1.mail.example.net", priority = 10 },
    { content = "mx2.mail.example.net", priority = 20 },
  ]
  TXT = [{ content = "v=spf1 include:_spf.mail.example.net -all" }]

  "google._domainkey.TXT" = [
    { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
  ]
  "_dmarc.TXT" = [
    { content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com" },
  ]
}
```

A website behind the Cloudflare proxy, with `www` pointing to the apex:

```hcl
"@" = {
  A       = [{ content = "192.0.2.10", proxied = true }]
  ALIASES = [{ content = "www", proxied = true }]
}
```

Certificate authority restrictions and the ACME DNS challenge of a certificate for `app.example.com`:

```hcl
"@" = {
  CAA = [
    { content = "letsencrypt.org", tag = "issue" },
    { content = "letsencrypt.org", tag = "issuewild" },
    { content = "mailto:security@example.com", tag = "iodef" },
  ]
}
"app" = {
  A                     = [{ content = "192.0.2.30" }]
  "_acme-challenge.TXT" = [{ key = "acme", content = "challenge-token" }]
}
```

A service advertised with SRV:

```hcl
"_sip._tcp" = {
  SRV = [{
    data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
  }]
}
```

### Next to external-dns

The module manages only the records in its configuration and leaves the others alone, so a controller such as [external-dns](https://github.com/kubernetes-sigs/external-dns) can manage records of the same zone, for example for Kubernetes ingresses. Give each its own names, so they never write the same record:

- Let external-dns manage a subdomain (`--domain-filter=k8s.example.com`), or restrict it to annotated resources, and keep those names out of `records`.
- external-dns keeps a TXT ownership record next to each record it manages (`--txt-owner-id`, `--txt-prefix`); leave these to it as well. A `CNAME` in `records` on a name that external-dns also uses fails at apply, and two tools writing the same `A` record overwrite each other.
- With [`report_unmanaged`](#records-not-in-the-configuration), the records of external-dns show up as unmanaged. Leave its part of the zone out of [`owned_names`](#the-part-of-the-zone-a-module-call-owns), so that the module cannot write there and the report does not look there, and leave its TXT ownership records on shared names out of the report with `unmanaged_ignore`:

  ```hcl
  owned_names      = { include = ["@"], exclude = ["k8s"] }
  unmanaged_ignore = [{ name_regex = "^extdns-", types = ["TXT"] }] # --txt-prefix=extdns-
  ```

### Internationalized Names

The module expects internationalized names in Punycode, as the Cloudflare API does. The `idna` submodule takes them in Unicode instead: it converts them with `provider::idna::to_ascii` of the [`5xxeu/idna`](https://registry.terraform.io/providers/5xxeu/idna/latest) provider and passes everything to the v5 wrapper. The provider has only functions (Terraform 1.8 or later): no configuration and no network requests, but `terraform init` installs it, which is why the root module does not use it.

```hcl
module "dns" {
  source  = "5xxeu/ezdns/cloudflare//modules/dns/idna"
  version = "2.13.0"

  zone_id   = var.zone_id
  zone_name = "münchen.de" # or null: the zone is looked up and its name converted
  records = {
    "@"      = { A = [{ content = "192.0.2.1" }], MX = [{ content = "mx.münchen.de", priority = 10 }] }
    "bücher" = { CNAME = [{ content = "www.münchen.de" }] }
  }
}
```

The plan shows the converted names, which are also in the record keys:

```text
  # module.dns.module.v5.cloudflare_dns_record.record["@ A 192.0.2.1"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["@ MX mx.xn--mnchen-3ya.de"] will be created
  # module.dns.module.v5.cloudflare_dns_record.record["xn--bcher-kva CNAME"] will be created
```

- It has the inputs and outputs of the root module. `zone_name`, names, prefixes of record types (`"straße.A"`), `ALIASES`, the `content` of `CNAME`, `MX`, `NS` and `PTR` records, `target` of `SRV`, `HTTPS` and `SVCB` and `replacement` of `NAPTR` in `data`, the host of a `URI` target, `allowed_cname_conflicts` and `owned_names` are converted, in `records` and in `record_groups`. Other values (TXT content, comments) stay as written.
- Only values with non-ASCII characters are converted. Record keys contain the converted form (`xn--bcher-kva CNAME`), the same as for names written in Punycode in lower case, and names in ASCII keep their keys as written, so a configuration can switch to Unicode names without changing addresses in the state.
- Its module call inside is named `v5`, like in the root module, so the records have the same addresses (`module.dns.module.v5.cloudflare_dns_record.record[...]`): switching `source` between the root module and `//modules/dns/idna` needs no `moved` blocks. Run `terraform init -upgrade` and check that the plan shows no changes.
- Errors show the converted names (`records["xn--bcher-kva"]["A"][0]`). A name written in both forms (`bücher` and `xn--bcher-kva`) is the same name, and the same record under both fails as a duplicate.

Without the submodule, the same provider converts names in the configuration of the module call:

```hcl
terraform {
  required_providers {
    idna = {
      source  = "5xxeu/idna"
      version = "~> 0.1"
    }
  }
}

locals {
  records = {
    "@"      = { A = [{ content = "192.0.2.1" }] }
    "bücher" = { CNAME = [{ content = provider::idna::to_ascii("www.münchen.de") }] }
  }
}

module "dns" {
  source  = "5xxeu/ezdns/cloudflare"
  version = "2.13.0"

  zone_id   = var.zone_id
  zone_name = provider::idna::to_ascii("münchen.de")
  records   = { for name, types in local.records : provider::idna::to_ascii(name) => types }
}
```

- An internationalized zone must set `zone_name` here, see [Requirements](#requirements).
- `to_ascii` keeps `@`, a `*` wildcard and labels such as `_acme-challenge`, so it can convert every name. Convert the names, but not the record types under them: `to_ascii` would write `"_acme-challenge.TXT"` in lower case. An internationalized prefix of a type is converted on its own (`"${provider::idna::to_ascii("straße")}.A"`). Convert targets where they are written: `content` of `CNAME`, `MX`, `NS`, `PTR` and `ALIASES`, `target` of `SRV`, `HTTPS` and `SVCB` and `replacement` of `NAPTR` in `data`. A `URI` target is a URI: convert only its host (`"https://${provider::idna::to_ascii("münchen.de")}/path"`).
- Record keys contain the converted form (`xn--bcher-kva CNAME`). A configuration that wrote these names and targets in Punycode in lower case can switch to the readable form without changing addresses in the state. Keys keep a name as written, so a name written in another form (`XN--BCHER-KVA`) gets a new key: keep the record with a `moved` block, see [Record Keys](#record-keys).
- With records in YAML, convert the names of the decoded map the same way. The JSON Schema accepts names in Punycode only, so the editor marks names in Unicode.

## Importing Existing Records

When the zone already has records, the first `apply` would fail with "record already exists" for each of them. With provider v5 (the root module or the `v5` submodule), the module can find the existing records and adopt them into the state instead. It works the same with records in HCL or in YAML; see [`examples/import`](https://github.com/5xxeu/terraform-cloudflare-ezdns/tree/main/examples/import).

> **`import_existing` does not import anything by itself.** It only finds the IDs of existing records and exposes them in `import_ids`; the `import` block in step 2 does the import. It is not a reconciliation either: records of the zone that are not in `records` are left alone.

Each lookup reads up to 100,000 records of one type (10,000 before 2.13.0), a limit of the module; in a zone with more records of a configured type, the rest are not found and would be created again. When a lookup returns 100,000 records, `plan` stops: set `import_existing = false` and import the records with `import` blocks of their own.

1. Set `import_existing = true`. The module then reads the records of the zone (the API token needs the `DNS Read` permission) and matches them to the configured records by name, type and value. The records are read with one request per record type of the configuration, which avoids a provider crash on zones with CAA records ([cloudflare/terraform-provider-cloudflare#7004](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004)).
2. Add an `import` block next to the module call:

   ```hcl
   import {
     for_each = module.dns.import_ids
     to       = module.dns.module.v5.cloudflare_dns_record.record[each.key]
     id       = each.value
   }
   ```

   With the `//modules/dns/v5` submodule, the address has no `module.v5`: `module.dns.cloudflare_dns_record.record[each.key]`.

3. Run `terraform plan`. Existing records are shown as imported, and only records missing in the zone are created. Check that no record you expect to be imported is shown as created:

   ```text
     # module.dns.module.v5.cloudflare_dns_record.record["@ MX mx.example.net"] will be imported
     # module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"] will be imported
     # module.dns.module.v5.cloudflare_dns_record.record["new A 192.0.2.20"] will be created

   Plan: 2 to import, 1 to add, 0 to change, 0 to destroy.
   ```
4. Run `terraform apply`, then remove the `import` block and `import_existing`, so the zone is not read on every plan.

For structured records (`SRV`, `HTTPS`, `TLSA`, ...), provider v5 plans a one-time in-place update right after the import, without visible changes; after the `apply`, the plan is empty.

Matching ignores the case and a trailing dot of names, hostnames (`target`, `replacement`, the issuer domain of CAA `issue`/`issuewild` values) and hex values (`digest`, `fingerprint`, and `certificate` of TLSA and SMIMEA records); other `data` fields (also the `target` of URI records, whose paths are case-sensitive), CAA parameters after `;`, `iodef` URLs and OPENPGPKEY keys must match exactly. IPv6 addresses are compared in their canonical form (`2001:0db8:0:0:0:0:0:1` is `2001:db8::1`). TXT values in the zone file form, one or more quoted chunks (`"v=spf1 \"a\" -all"`, `"v=spf1 a" " -all"`), are compared as the chunks joined without their quotes and escapes, since Cloudflare stores TXT content as it was sent and `v=spf1 "a" -all` is the same DNS record; any other value is compared exactly, quotes included (`prefix" "suffix` is not `prefixsuffix`). A TXT record stored in the quoted form and configured without quotes gets a one-time in-place update to the configured form after the import (the DNS answer does not change). An existing record is imported into one address only: configured records that differ only in `priority` (`MX`, `URI`) match the same existing record, which goes to the one with the same priority, while the others are created; without such a record, the import is ambiguous. In the same way, a record with a priority that matches several existing records (MX 10 and MX 20 on one host) takes the one with its priority. A record is imported only when its match is unambiguous. When it is not, for example when the zone has several identical records, `plan` stops (from 2.11.0; before, it showed a warning and planned the record as created) and lists the records with the IDs of all their matches. Remove the duplicates from the zone or give the records distinct values or priorities; to import such a record anyway, set `import_existing = false` and write an `import` block for it. The `import_duplicates` output has the same list.

### Writing the Configuration of an Existing Zone

The import adopts the records that the configuration describes, so a zone with many records needs that configuration first. `tools/zone-to-ezdns.py` (Python 3.8 or later, no packages) writes it from the records that the Cloudflare API returns:

```console
$ curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=5000000" > zone.json
$ python3 tools/zone-to-ezdns.py zone.json --zone example.com --default-ttl 3600 > records.ezdns.yaml
zone-to-ezdns: skipped NS example.com (372e67954025e0ba6aaa6d586b9e0b59): read only, managed by Cloudflare
```

For a zone with a proxied apex and `www`, two MX records on one host, an SPF record with a TTL of 300 and an SRV record, `records.ezdns.yaml` is:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/5xxeu/terraform-cloudflare-ezdns/main/schema/records.schema.json
# Records of example.com written by zone-to-ezdns.py (6 records). Review them, then adopt them with
# import_existing = true and import blocks, and check that the plan creates and deletes nothing.
records:
  "@":
    A:
      - content: "192.0.2.10"
        proxied: true
    MX:
      - content: "mx.example.net"
        key: "priority-10"
        priority: 10
      - content: "mx.example.net"
        key: "priority-20"
        priority: 20
    TXT:
      - content: "\"v=spf1 mx -all\""
        ttl: 300
  "_sip._tcp":
    SRV:
      - data:
          priority: "10"
          weight: "5"
          port: "5060"
          target: "sip.example.com"
  "www":
    CNAME:
      - content: "example.com"
        proxied: true
```

The script exits with 1 when it skipped records or found copies (the file is written anyway), so a CI step can stop on it, and with 2 when the input cannot be read, has a record of an unexpected shape or is one page of a longer list (nothing is written).

- Every value is quoted, so YAML 1.1 keeps it as text. Records with the TTL of `--default-ttl` (the `default_ttl` of the module call) are written without one, proxied records without TTL. The proxy status of `A`, `AAAA` and `CNAME` records is written both ways (`proxied: false` too), so a `default_proxied = true` or the defaults of a group do not change a record of the zone.
- `MX` and `URI` records that differ only in priority, and `CAA` records that differ only in flags, get a `key` each, since they would have the same record key. When these keys repeat within a name and type (two MX hosts, each with priorities 10 and 20), the target goes into the key (`mx1.example.com-priority-10`). Copies of one record in the zone (also with another TTL, comment or tags) are written once and reported with their IDs, not their values (the value of a proxied record is its origin address): the import of such a record stops until the zone has one copy.
- Records that the module does not manage are left out and reported: read-only records of Cloudflare, records outside the zone and types that the module does not support.
- The output of [`unmanaged_records`](#records-not-in-the-configuration) has the same form, without TTL, proxy status, comments and tags. Records written from it get the module defaults, so check them before the import: a proxied record written as not proxied would publish its origin address after the apply.

Then review the file, pass it to the module and adopt the records as described above; the plan must import every record and create none. Consider giving a `key` to records whose values will change (see [Record Keys](#record-keys)).

## Records Not in the Configuration

With `report_unmanaged = true` (provider v5), the module reads the records of all types in the zone and lists those that no configured record matches, in the `unmanaged_records` output (`id`, `name`, `type`, `content`, `priority`, `data`) and in a `plan` warning. The warning shows the type, name and ID only (the first 50 records), and the output is sensitive: the content of a proxied record is the origin address that Cloudflare hides from DNS, and plans often end up in CI logs. Records are compared like in [import](#importing-existing-records); a configured `MX` or `URI` record describes the records of its priority (an `MX 20` next to the configured `MX 10` is listed, also when `import_existing` offers it for import: the module cannot see whether an `import` block adopts it). Without `import_existing`, the warning also lists configured records that match several records in the zone (copies of the same record, or a record described too loosely, such as a structured record without a field that tells two records apart), with type, name and IDs; with it, they stop the plan. The warning shows on `plan` and on `apply` while `report_unmanaged` is set. Nothing is deleted: Terraform can only delete records that are in its state, and deleting records outside it could remove the records of other tools (see [Next to external-dns](#next-to-external-dns)). For each listed record, add it to `records` and adopt it with an `import` block (`import_existing` gives the import IDs, see [Importing Existing Records](#importing-existing-records)), or delete it yourself.

To read the values, pass the output through in the root module and read it from a saved plan (`terraform output` only shows the state of the last `apply`):

```hcl
module "dns" {
  source           = "5xxeu/ezdns/cloudflare"
  version          = "2.13.0"
  zone_id          = var.zone_id
  report_unmanaged = true
  records          = { "@" = { A = [{ content = "192.0.2.1" }] } }
}

output "unmanaged_records" {
  value     = module.dns.unmanaged_records
  sensitive = true
}
```

The plan warns with the type, name and ID of each record:

```text
Warning: Check block assertion failed

The zone has 2 records that the configuration does not describe (records of
other tools, such as external-dns, are listed too). Add them to records and
adopt them with import blocks (import_existing gives their IDs), or delete
them yourself. Their values are in the sensitive unmanaged_records output:
pass it through as a root module output, then terraform plan -out=tfplan
and terraform show -json tfplan:
A old.example.com (372e67954025e0ba6aaa6d586b9e0b59)
TXT example.com (9a7806061c88ada191ed06f989cc3dac)
```

```console
$ terraform plan -out=tfplan
$ terraform show -json tfplan | jq '.planned_values.outputs.unmanaged_records.value'
[
  {
    "content": "192.0.2.9",
    "data": null,
    "id": "372e67954025e0ba6aaa6d586b9e0b59",
    "name": "old.example.com",
    "priority": null,
    "type": "A"
  },
  {
    "content": "google-site-verification=abc",
    "data": null,
    "id": "9a7806061c88ada191ed06f989cc3dac",
    "name": "example.com",
    "priority": null,
    "type": "TXT"
  }
]
```

The report needs the `DNS Read` permission and makes one lookup per record type (21) on every plan, and the provider reads the records of a type in pages, so a large zone takes more requests. Turn it on when reviewing the zone or in a scheduled CI job rather than on every plan. Like the import, a lookup that returns 100,000 records of one type (the limit) stops the plan, since the report would be incomplete. Records that Cloudflare manages itself and does not return as DNS records (the zone's own name servers) are not listed.

Records that are expected in the zone can be left out of the report with `unmanaged_ignore`: a record is left out when it matches all fields of an entry, `name_regex` (RE2, matched against the fully qualified name in lower case without a trailing dot; unanchored, so use `^` and `$`) and `types`:

```hcl
unmanaged_ignore = [
  { name_regex = "^_acme-challenge\\.", types = ["TXT"] }, # cert-manager
  { types = ["NS"], name_regex = "^dev\\.example\\.com$" }, # a delegation managed elsewhere
]
```

With `unmanaged_policy = "error"`, the report stops the plan instead of showing a warning, with the same list and the line `unmanaged_policy is "error", so the plan stops.` Use it in CI for a zone (or the [part of a zone](#the-part-of-the-zone-a-module-call-owns)) that only this configuration may change: a record added by hand in the dashboard then fails the next plan until it is added to the configuration or deleted.

### The Part of the Zone a Module Call Owns

When several teams or tools share a zone, `owned_names` limits a module call to its part of it: the names in `include` and below them, except the names in `exclude` and below them. Names are written like in `records` and compared fully qualified, case-insensitively and by whole labels, so `apps` covers `web.apps` but not `myapps`:

```hcl
owned_names = {
  include = ["apps"]     # apps.example.com and everything below it
  exclude = ["k8s.apps"] # except the part that external-dns manages
}
```

- A configured record outside this part fails at `plan`, with the name and where the record is defined. A typo in a name cannot create a record in the part of another team:

  ```text
  Error: Module output value precondition failed

  These records are outside owned_names (included: apps.example.com; excluded:
  k8s.apps.example.com), the part of the zone that this module call manages:
  "api.k8s.apps.example.com" (A) from records["api.k8s.apps"]["A"][0]
  "app.example.com" (A) from records["app"]["A"][0]
  ```
- [`report_unmanaged`](#records-not-in-the-configuration) only looks at this part: records of other teams and tools are not reported as unmanaged.
- `owned_names` is a rule of the configuration, not a lock: another tool can still write into this part of the zone. `null` (the default) is the whole zone.

## Checking Plans Before Apply

The module validates the records it is given, but it cannot see what a plan does to the records already in the state: a deleted or renamed YAML file, a changed name form or a removed module call deletes records, and the configuration is still valid. `tools/plan-guard.py` (Python 3.8 or later, no packages) reads a saved plan and fails when the plan deletes or replaces records, turns off the proxy of a record (which publishes its origin address), or leaves a required record set empty:

```sh
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
python3 tools/plan-guard.py tfplan.json --zone example.com --require @:MX --require @:A
terraform apply tfplan
```

A plan after the YAML file with the MX records was deleted, the address of `app` changed without a `key`, and `proxied` removed from `www`:

```console
$ python3 tools/plan-guard.py tfplan.json --zone example.com --require @:MX
The plan deletes 3 records (allowed: 0):
  module.dns.module.v5.cloudflare_dns_record.record["@ MX mx1.mail.example.net"]
  module.dns.module.v5.cloudflare_dns_record.record["@ MX mx2.mail.example.net"]
  module.dns.module.v5.cloudflare_dns_record.record["app A 192.0.2.10"]
The plan turns off the proxy of records, which publishes their origin address (--allow-proxy-disable allows it):
  module.dns.module.v5.cloudflare_dns_record.record["www CNAME"]
MX records of example.com: 0 after the apply, at least 1 required
$ echo $?
1
```

A plan without such changes prints `plan-guard: the plan passes` and exits with 0. In CI, run it between `plan` and `apply`:

```yaml
# GitHub Actions
- run: terraform plan -out=tfplan
- run: terraform show -json tfplan > tfplan.json
- run: python3 .terraform/modules/dns/tools/plan-guard.py tfplan.json --zone example.com --require @:MX
- run: terraform apply tfplan
```

With the module from the Terraform Registry or Git, `terraform init` puts the script into `.terraform/modules/<module name>/tools/`; with a [local copy](#local-copy), it is in `modules/ezdns/tools/` (full archive).

- `--max-deletes N` and `--max-replacements N` allow up to N deletions or replacements (default 0). A changed value without a `key` is a deletion and a creation, so it counts as a deletion.
- `--allow ADDRESS` leaves out the changes of resources whose address matches (`*` matches any characters, e.g. `--allow 'module.dns.*["www A *"]'`), for a change that was reviewed.
- `--allow-proxy-disable` allows turning off the proxy. Without it, the plan also fails when a proxied record is replaced, deleted, moved or loses its proxy (also one allowed by `--allow`) and an unproxied `A`, `AAAA` or `CNAME` record on its name publishes something new: it is created, moved there, or gets another type or content (a changed value without a `key`, another record type, a renamed record). An unproxied record that stays as it was counts too when the name keeps no proxied `A`, `AAAA` or `CNAME` record that exists through the apply: while one is proxied, Cloudflare answers for the whole name (a new proxied record does not count, and neither does one that is replaced: Terraform deletes the old one first, unless the resource has `create_before_destroy`). The plan also fails when a proxy status is not known until apply. Without `--zone`, the apex (`@`) is taken to match every name, as the script cannot tell `@` from the zone name.
- `--require NAME:TYPE[:MIN]` requires at least MIN records (default 1) of a type on a name after the apply, with names as in `records` and `--zone` to qualify them. When the plan has records of several zones, give `--zone-id ID` to count the records of one zone; `--zone` then qualifies only the names of that zone, and the names of the other zones are compared without it. When the zone of records is known only after apply (a zone created in the same plan), `--require` fails, as such zones cannot be told apart: apply the zone first.
- `--module module.dns` checks only the records of one module call, with all its instances when it has `count` or `for_each` (`module.dns[0]`, `module.dns["prod"]`); `--module 'module.dns["prod"]'` checks one instance. A record moved out of the module by a `moved` block is still checked. Records of other module calls on the same names still count for the proxy check, as the proxy hides a whole name.

Apply the checked plan file (`terraform apply tfplan`), not a new plan: a new plan can differ from the checked one. The script checks `cloudflare_dns_record` and `cloudflare_record` resources of any configuration, also outside the module. Exit status 1 means the plan has changes that are not allowed, 2 that the plan cannot be read, has an unexpected structure or the arguments are wrong.

## Stability

The module follows [Semantic Versioning](https://semver.org/): within 2.x, record keys and therefore the addresses in the state stay the same, inputs and outputs are only added, and a change that can fail a plan that passed before is described in [Upgrading and Migration](#upgrading-and-migration) (stricter validation of values the API would reject anyway). Many 2.x releases were made in September and October 2026; the record keys have not changed since 2.0. Each release passes the tests on Terraform 1.8 and the latest version, the end-to-end test against a real Cloudflare zone, and a review before the merge.

Pin `version` exactly (or to a minor version, `~> 2.13.0`) and read the [CHANGELOG](https://github.com/5xxeu/terraform-cloudflare-ezdns/blob/main/CHANGELOG.md) before upgrading. Renovate and Dependabot update Registry and Git sources; [release archives](#local-copy) are upgraded by hand.

## Upgrading and Migration

### Upgrade Path

Do one step at a time, each with its own `terraform plan` and `apply`, and review every plan: it must not destroy or create records.

1. **From v1 to v2** (record keys): [v1 to v2](#from-v1-to-v2), staying on the submodule you already use. Targeting 2.6 or later, fix any [unknown attributes](#to-26-unknown-attributes) as part of this step.
2. **From provider v4 to v5**, if you use the `v4` submodule: [provider v4 to v5](#from-provider-v4-to-v5).
3. **To the root module**, optionally: [v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module).

Configurations that use the module from an earlier address (the repository `i386dev/terraform-cloudflare-easy-dns` or the Registry source `NikitaPuglachenko/easy-dns/cloudflare`) only change `source`, see [from an earlier address](#from-an-earlier-address).

For example, a configuration on `//modules/dns/v5` of v1 does step 1 with `RESOURCE=cloudflare_dns_record` and may stay on the submodule. From 2.0–2.5, upgrading to 2.6 or later only needs the [unknown attributes](#to-26-unknown-attributes) fixed, if there are any.

### From v1 to v2

Version 2 changes the record keys in the state (see [Record Keys](#record-keys)). Without migration, Terraform would destroy and recreate every record. The `state_migration` output maps the old keys to the new ones, so the migration can be done with `moved` blocks:

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

### To 2.13: Ranges of Data Fields, Unused Attributes

> **Configurations with out-of-range `data` values:** `plan` now fails for them, e.g. an SRV `port` of 70000 or a CAA `flags` of 256.

Numeric fields of structured records are checked against their ranges (see [Validation](#validation)). Such values were rejected by the Cloudflare API at apply before, so a configuration that applies today is not affected, unless it has a record that has never been applied. Attributes that do not apply to the type of a record (`content` of an SRV record, `priority` of an A record, `tag` of a TXT record) now show a warning; they were ignored before and still are, and will fail from 3.0, so remove them.

The `records` output has more attributes (`zone_id`, `fqdn`, `ttl`, `proxied`, `priority`, `data`), and the lookups of `import_existing` and `report_unmanaged` read up to 100,000 records per type instead of 10,000. No addresses in the state change.

### To 2.11: Ambiguous Imports Stop the Plan

> **Configurations with `import_existing = true`:** if `plan` showed a warning about records that match several existing records, or about a lookup that returned 10,000 records, it now fails with the same list.

An ambiguous import used to plan the record as created, which fails at apply or leaves two copies of it in the zone. Remove the duplicates from the zone, give the records distinct values or priorities, or set `import_existing = false` and adopt these records with `import` blocks; see [Importing Existing Records](#importing-existing-records). Configurations without `import_existing`, and those whose plans showed no such warning, are not affected.

### To 2.8: Minimum TTL

> **Enterprise zones with TTLs from 30 to 59 seconds:** set `minimum_ttl = 30` in the module call before upgrading, or the plan fails.

TTLs below 60 seconds (other than `1`, automatic) are rejected at `plan` unless `minimum_ttl = 30`. Cloudflare accepts them only on Enterprise zones, so on other plans such a TTL already failed at the API; now the plan says what to change. The module cannot see the plan of a zone without an extra API call, hence the explicit setting.

### To 2.7: Names in Lower Case

Record names are sent in lower case, as Cloudflare stores them. With provider v5, a name written in another case (`M1._domainkey`) showed a change on every plan that `apply` did not settle; that diff is gone. With the v4 wrapper, such a record gets a one-time in-place update of its name. Keys keep the name as written, so no state address changes.

### To 2.6: Unknown Attributes

Since 2.6, a record attribute that the module does not know fails the plan, e.g. `records["app"]["A"][0]: unknown attribute "proxid"`. Before, Terraform silently dropped such attributes, so a misspelled optional attribute had no effect. Fix the reported attributes: the plan then shows whether the corrected attributes change any records (e.g. a record that was meant to be proxied). For records in YAML, the [JSON Schema](#records-in-yaml) highlights these mistakes in the editor.

### From Provider v4 to v5

The v5 wrapper contains a `moved` block from `cloudflare_record` to `cloudflare_dns_record`, so the state is migrated without recreating records:

1. Upgrade the Cloudflare provider to `~> 5.26`.
2. Change the module `source` from `//modules/dns/v4` to `//modules/dns/v5`, keeping the module name the same. To go straight to the root module, also add the `moved` block from [the v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module), with `cloudflare_record` in `from`.
3. Run `terraform init -upgrade` and `terraform plan`. The plan should only show moved resources, without destroying or creating records; provider v5 also plans a one-time in-place update of the moved records (e.g. CAA `flags` become numbers). Review it carefully before applying.
4. Run `terraform apply`. Provider v5 (checked with 5.26) may report `Provider produced inconsistent result after apply` with `.modified_on` for some records: the timestamp in the migrated state has a different precision ([cloudflare/terraform-provider-cloudflare#7387](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387)). The records are updated anyway; run `terraform plan` again, it should show no changes.

### From an Earlier Address

Up to 2.12.0, the module was developed in `i386dev/terraform-cloudflare-easy-dns`, and up to 2.6.0 it was published on the Terraform Registry as `NikitaPuglachenko/easy-dns/cloudflare`, which is no longer available. The repository now is `5xxeu/terraform-cloudflare-ezdns`, with all earlier tags, and the Registry source is `5xxeu/ezdns/cloudflare`. Git sources of the old repository and the archives of its releases keep working, but new versions are published only here.

Change `source` to the [Terraform Registry](#terraform-registry) (with `version`), a [Git source](#git-source) of the new repository or a [local copy](#local-copy) of the same version, keeping the module name and the path (root module or `//modules/dns/v4`, `//modules/dns/v5`): the module is the same, so no addresses in the state change. Run `terraform init -upgrade`, and `terraform plan` shows no changes. The module is now called ezdns: the README suggests `modules/ezdns` for a local copy and `*.ezdns.yaml` for records in YAML, but an existing copy in `modules/easy-dns` and existing `*.easy-dns.yaml` mappings keep working, since neither affects the state.

### From the v5 Submodule to the Root Module

The root module wraps the v5 submodule, so its records have one more level in their address. When switching `source` from the `v5` submodule (`./modules/ezdns/modules/dns/v5` or `//modules/dns/v5` in a Git source) to the root module, add a `moved` block next to the module call, so the records are not recreated:

```hcl
moved {
  from = module.dns.cloudflare_dns_record.record
  to   = module.dns.module.v5.cloudflare_dns_record.record
}
```

Run `terraform init -upgrade` and `terraform plan`: it should only show records that have moved. After `terraform apply`, the `moved` block can be removed. Staying on the submodule is fine as well.

## Testing

The core module, both wrappers and the examples have plan-only tests (the wrappers and examples use a mocked provider), no Cloudflare credentials needed. The core module's tests also pin the invariants of name normalization (`names.tftest.hcl`: every form of a name gives one fully qualified name) and record identity (`identity.tftest.hcl`: reordering records keeps their keys, a `key` keeps the address when the value changes, YAML and HCL give the same records):

```sh
cd modules/dns/v5
terraform init
terraform test
```

The module READMEs are generated with [terraform-docs](https://terraform-docs.io), and the JSON Schema with a script that reads the record types and `data` fields from the records module. After changing variables, outputs, requirements or record types, regenerate them:

```sh
./scripts/generate-docs.sh
python3 scripts/generate-schema.py
python3 scripts/test-schema.py   # requires jsonschema and pyyaml
python3 scripts/test-schema.py --terraform   # the same documents through the module: schema and validation must agree
```

The scripts in `tools` have unit tests (`python3 -m unittest discover -s tools/tests`), and the YAML that `zone-to-ezdns.py` writes from a fixture goes through the module in CI.

CI runs `terraform fmt`, `validate` and `test` for the root module, the core module, the `compile` and `idna` submodules, both wrappers and the examples (on Terraform 1.8 and the latest version, and on the minimum supported provider versions), checks that the module READMEs and the JSON Schema are up to date, tests the schema and the tools, checks that the root module, the wrappers and the submodules have the same interface, [TFLint](https://github.com/terraform-linters/tflint) and [Gitleaks](https://github.com/gitleaks/gitleaks) on every pull request.

### Testing Your Records

The `compile` submodule runs the checks of the wrappers on a configuration and returns its records as the wrappers would create them, keyed by their record keys, without a provider and without credentials. A test of your own configuration can then check what matters for your zone:

```text
records.ezdns.yaml        # the records, also used by the module call that manages the zone
tests/
├── compile/main.tf       # the compile submodule with the same records
└── dns.tftest.hcl        # assertions about the records
```

```hcl
# tests/dns.tftest.hcl, next to records.ezdns.yaml
run "zone" {
  command = plan

  module {
    source = "./tests/compile"
  }

  assert {
    condition     = length([for r in module.compiled.records : r if r.type == "MX"]) >= 2
    error_message = "The zone needs at least two MX records"
  }

  assert {
    condition     = !anytrue([for r in module.compiled.records : r.proxied if startswith(r.fqdn, "mail.")])
    error_message = "Mail hosts must not be proxied"
  }
}
```

```hcl
# tests/compile/main.tf
module "compiled" {
  source  = "5xxeu/ezdns/cloudflare//modules/dns/compile"
  version = "2.13.0"

  zone_name = "example.com"
  records   = yamldecode(file("${path.module}/../../records.ezdns.yaml")).records
}
```

```console
$ terraform init
$ terraform test
tests/dns.tftest.hcl... in progress
  run "zone"... pass
tests/dns.tftest.hcl... tearing down
tests/dns.tftest.hcl... pass

Success! 1 passed, 0 failed.
```

Pass the same inputs as to the module call that manages the zone (`record_groups`, the defaults, `owned_names`, ...), so the test sees the same records. Invalid records fail the test like they fail the plan, and a failed assertion shows its `error_message` (`Mail hosts must not be proxied`) with the records it checked.

### End-to-End Tests

`tests/e2e/run.sh` runs against a real Cloudflare zone. Under a label of the run (e.g. `e2e-1234.example.com`), it:

1. Creates records of every type through the root module and checks that a second `plan` shows no changes (no drift in the provider).
2. Changes values: a record without a `key` is replaced, a record with a `key` is updated in place.
3. Adopts the same records into an empty state with `import_existing` and checks that all of them are imported, none created, and each one under the ID of the record created in step 1.
4. Creates records with the v4 wrapper and opens the state with the v5 wrapper: the records must be moved, not recreated, and keep their keys and Cloudflare IDs.
5. Deletes everything. `tests/e2e/sweep.sh` also removes records left by failed runs; it only deletes records with the comment `ezdns-e2e` and a run label in the name.

```sh
CLOUDFLARE_API_TOKEN=... E2E_ZONE_ID=... E2E_ZONE_NAME=example.com tests/e2e/run.sh
```

The token needs the `DNS Edit` permission on the zone. In CI, the test runs weekly and on demand (never for pull requests), with the token stored in the `cloudflare-e2e` environment.

## License
MIT
