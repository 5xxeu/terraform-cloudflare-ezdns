# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- `tools/plan-guard.py`: an `A`, `AAAA` or `CNAME` record whose proxy status is known only after apply fails the plan also when it is new or was not proxied, and its value counts as hidden by the proxy: a new unproxied record with the same value fails, and `--strict-proxy` checks the new unproxied records next to it. Before, such a record passed, and so did an unproxied record with its address, also with `--strict-proxy`

- The JSON Schema rejects empty `content` for TXT, OPENPGPKEY and CAA records, matching the module validation

- CI fails on warnings from generated records both with and without `--stable-keys`: the check after the first run did not fail the step

- Release tags with a prerelease suffix are marked as prereleases on GitHub

- Registry version comments in the v5, YAML and import examples use 2.19.0

- `README.md` and `SECURITY.md` say that the release workflow gates the GitHub Release and the archives, while the Terraform Registry picks up a pushed version tag on its own

## [2.19.0] - 2026-10-25

### Added

- `tools/plan-guard.py --unmanaged OUTPUT`: an exact check of the records of the zone by Cloudflare IDs. The records in the passed-through `unmanaged_records` and `presumed_previous_records` outputs whose IDs are not in the state of the saved plan and are not imported by it fail the plan, so a record added by hand next to a record that the plan creates fails on the same plan, and the old value of a changed record never does (see `docs/plan-guard.md`)

### Fixed

- `unmanaged_ignore` also leaves copies of a configured record out of the report: copies on an ignored name and type no longer stop the plan with `unmanaged_policy = "error"` or show in the warning. With `import_existing`, copies still stop the plan, since the import needs one match

### Internal

- Core changes run plain, groups and import benchmarks in CI, blocking time or peak memory regressions over 2x a stored runner baseline; each workload is the median of three plans

- End-to-end tests run `plan-guard --unmanaged`: a record added by hand next to new records is listed, old values of changed records are not, the stray record is

- End-to-end tests check upgrades from the previous release without recreating records or changing their Cloudflare IDs; mocked tests cover record identity across groups

### Changed

- The README starts with what the module adds over plain resources and has a Guarantees and Limits section: what is guaranteed, what is a best-effort check (`report_unmanaged`, `tools/plan-guard.py`) and what Terraform and the Cloudflare API do not allow. `docs/unmanaged-records.md` lists what the report sees in common situations, and no longer promises that `unmanaged_policy = "error"` fails the next plan for every record added by hand: a record added on the name and type of a record that the same plan creates is reported one plan later (a mocked test covers it)

- The README keeps how the module works, a quick start, the requirements, the sources and when not to use it; the reference moved to `docs`: the record model (`docs/record-model.md`), validation (`docs/validation.md`), inputs and outputs (`docs/reference.md`), records in YAML and in several files (`docs/yaml.md`), the local copy and the Git source (`docs/sources.md`), and the full example (`docs/examples.md`). The structure of the repository is in `CONTRIBUTING.md`. Links to the moved README sections need the new pages; the error for unknown or missing `data` fields points to `docs/record-model.md`

## [2.18.0] - 2026-10-20

### Added

- `require_keys` input: record types whose records must have a `key`, e.g. `["A", "AAAA", "TXT"]`. A record of these types without a `key` fails at `plan` with where it is defined; `CNAME` and `ALIASES` are keyed by name and cannot be listed. The default `[]` changes nothing

### Changed

- The first example of the README and the examples with server addresses give the address records a `key`, so a new address is an update in place

## [2.17.0] - 2026-10-20

### Added

- `presumed_previous_records` output (v5): IDs, names and types of existing records taken as old values during a value change and left out of `unmanaged_records`. The module cannot see the state, so a record added by hand may be among them

### Changed

- `tools/plan-guard.py` rejects errored plans, unsupported format versions and incomplete plans (including targeted plans); `--allow-incomplete` allows checking incomplete plans with the usual checks

### Internal

- CI tests Terraform 1.8.0, the promised minimum, and the latest version

## [2.16.4] - 2026-10-20

### Changed

- The v4 wrapper warns about the `settings` and `private_routing` of records (set to `true`): provider v4 has no such attributes, and the wrapper ignored them without a word

### Fixed

- Records with an explicit `key` are also compared by their values: two records with the same name, type and value (and priority, for `MX` and `URI`) under different keys now fail at `plan`, as Cloudflare rejects identical records at `apply`. A value known only after `apply` defers this check to `apply`, before the configured records are created or updated (records removed from the configuration may be deleted first)
- `private_routing = true` on a record that is not proxied now fails at `plan`; Cloudflare rejects it at `apply`

## [2.16.3] - 2026-10-19

### Fixed

- A `CNAME` at the zone apex next to an `A` or `AAAA` record now fails at `plan`, like on any other name; Cloudflare rejects it at `apply`. Other records (`MX`, `TXT`, ...) next to an apex `CNAME` are still allowed, and `allowed_cname_conflicts` still lets such a name through

### Internal

- Release workflow: only the highest version tag is marked as the latest release, and the checkout keeps no credentials. CI pins the Python packages of the schema check. The end-to-end test also covers `record_groups` and the `idna` submodule, and its cleanup matches the run label only as a whole part of a name

## [2.16.2] - 2026-10-19

### Fixed

- The same record written in two forms that the import takes for one record now fails at `plan` as a duplicate, like two name forms already did: a TXT value quoted and not quoted (`v=spf1 -all` and `"v=spf1 -all"`), a CAA issuer in another case, a hostname in `data` in another case or with a trailing dot, numbers in `data` written differently (`5060` and `"5060.0"`). Before, such records got two keys, and the second one failed at `apply` or made the import ambiguous. Records with a `key` are still compared by their keys
- `@` as the target of a `CNAME`, `MX`, `NS` or `PTR` record is sent as the zone name, and the import and the report of unmanaged records match it with the zone name; before, it was sent as `@` and never matched. The key keeps `@` as written
- Import and the report of unmanaged records compare numeric `data` fields as numbers: `port = "5060.0"` matches the `5060` that Cloudflare returns
- `tools/moved-blocks.py` exits with code 2 on a change that does not have the shape of a plan (actions as a string, unknown actions), like `plan-guard.py`; before, it skipped the record and exited with 0
- The JSON Schema requires the `records` key at the root, so a misspelled key no longer passes as a document without records

## [2.16.1] - 2026-10-18

### Fixed

- `record_groups` given as a list (`record_groups: []` in YAML) passed the validations as no groups and planned the deletion of every grouped record; it now fails at `plan`, like an explicit `null`. `records` given as a list also fails with a clear message instead of an error of `keys()` in the wrappers. Pass `{}` or leave the input out for no records (root module, both wrappers, `compile` and `idna`)

## [2.16.0] - 2026-10-18

### Added

- `tools/zone-to-ezdns.py --stable-keys`: every record but a CNAME gets a `key` from its Cloudflare ID (`cf-` and the first 8 characters), so a later change of its value updates the record in place instead of deleting and creating it
- A warning for a null MX (content `.`, RFC 7505) on a name that has other MX records too: Cloudflare accepts it, but RFC 7505 forbids other MX records next to a null MX

### Changed

- Releases: the release workflow also requires a passed end-to-end test of the tagged commit, and checks the archives before it publishes them (`scripts/check-archives.sh`: the files of the module are there, tests are not, the v5 archive has no v4 wrapper, both validate as modules)

### Fixed

- Plans no longer slow down quadratically with many records or `record_groups`: the merge of the groups, the checks of names and CNAME conflicts and the validations of `records` and `record_groups` in the wrappers no longer compare every record or name with all the others. 11,100 records in 10 groups plan in about 37 seconds instead of 203 (`tests/bench/groups`, see [Testing](docs/testing.md))

## [2.15.0] - 2026-10-17

### Added

- `ignore_changes` record attribute (provider v5): the listed attributes (`content` with `data`, `ttl`, `proxied`, `comment`, `tags`) come from the record in the zone instead of the configuration, so a value that a DDNS client or a change in the dashboard writes plans no change. Terraform allows only literals in `lifecycle`, so the module reads the records of the zone at every plan and finds the record by name and type: such a record is the only configured record of its type on its name, and a zone with several records of that name and type stops the plan. `import_existing` adopts the record whatever its value, and `report_unmanaged` does not list it. The v4 wrapper stops the plan for such records (provider v4 has no lookup of the records of a zone); `compile` returns the configured values. In the JSON Schema and the `records` output (the listed attributes as in the zone)
- A warning for two different SPF records on one name, or two DMARC records on a `_dmarc` name: Cloudflare accepts them, but every SPF check fails (RFC 7208) and the domain has no DMARC policy (RFC 7489)
- `docs/recipes.md`: a Cloudflare Tunnel record, and a table of the zone for a wiki from the `records` output

## [2.14.1] - 2026-10-17

### Added

- `tools/zone-to-ezdns.py --schema URL_OR_PATH`: the schema link written at the top of the YAML, such as the path of a local copy (`modules/ezdns/schema/records.schema.json`)

### Fixed

- `report_unmanaged`: a record whose value (or `MX`/`URI` priority) changes in the plan is no longer reported with its old value, which matched no configured record, so `unmanaged_policy = "error"` no longer stops an ordinary update. On a name and type, existing records without a match are taken as the old values while they are no more than the configured records without one (the state is not visible to the module); a record added by hand next to a new record is reported from the next plan on. The e2e test checks the report during a value change
- `import_existing` and `report_unmanaged` no longer slow down the plan quadratically: each configured record is compared only with the existing records of its name and type, and IDs are looked up by index. 3,000 configured and 4,000 existing records plan in about 8 seconds instead of 4 minutes (`tests/bench/import`, see [Testing](docs/testing.md))
- `tools/zone-to-ezdns.py` links the JSON Schema of its own module release instead of `main`, so an editor does not offer fields of a newer version
- e2e test: a failed `terraform destroy` or sweep at the end fails the run, also when every check passed, and the state files are kept so the records can still be destroyed

## [2.14.0] - 2026-10-13

### Added

- `tools/moved-blocks.py`: writes `moved` blocks from a saved plan for records that it deletes and creates again under another key (a `key` added, a name written in another form), pairing records by zone, fully qualified name, type and value; copies and values known only after apply are left to pair by hand
- `minimum_ttl = "auto"` (root module, both wrappers): the lowest TTL is taken from the plan of the zone, `30` on Enterprise zones and `60` on the others. The zone is read for it (Zone, Zone, Read). The type of `minimum_ttl` is now `string`: numbers still work as before (`minimum_ttl = 30`), and the default stays `60`, also for an explicit `null`. The `compile` module, which reads nothing, takes `30` for `"auto"`
- `private_routing` record attribute (provider v5; ignored by the v4 wrapper like `settings`): private network routing to the origin, passed to `cloudflare_dns_record`, in the JSON Schema, in the `records` output and written by `tools/zone-to-ezdns.py` for records that have it
- The `records` output has `comment`, `tags`, `settings` and `private_routing` of every record, as configured (known at plan; the last two are `null` with provider v4, which does not support them)
- `tools/plan-guard.py --strict-proxy`: when the plan has proxied records, every unproxied `A`, `AAAA` or `CNAME` record that is new or gets another name, type or content (and `HTTPS` or `SVCB` record with new address hints) fails until it is allowed with `--allow` or `--allow-proxy-disable`, whatever its value

### Fixed

- `record_names` output: the fully qualified names of the configuration with both wrappers. With provider v5 it had the names as written right after an apply and the fully qualified names after the next refresh, so the first plan after an apply showed a change of the output; with v4 it had the hostnames from Cloudflare. The e2e test checks it
- `tools/plan-guard.py`: a replacement with `destroy = false` (`["forget", "create"]`) whose new record is unproxied no longer fails as a proxy that is turned off, as the old proxied record stays; the new record is checked as a created one
- `tools/plan-guard.py`: a proxied record whose type is known only after apply now hides its value too, so a new unproxied record with that address or name fails

### Changed

- CODE_OF_CONDUCT.md: reports go to the private reporting of the repository

## [2.13.1] - 2026-10-13

### Fixed

- `tools/plan-guard.py`: an `HTTPS` or `SVCB` record that gets the address of a proxied record in `ipv4hint` or `ipv6hint` fails the plan, as it publishes the origin address (unless `--allow-proxy-disable` or `--allow`); service parameters known only after apply fail like an unknown value of an unproxied record
- `tools/plan-guard.py`: a record that a `removed` block forgets (`lifecycle { destroy = false }`) stays in Cloudflare, so it no longer fails as a proxy that is turned off, and it counts for `--require`; so does the old record of a replacement with `destroy = false` (`["forget", "create"]`)

## [2.13.0] - 2026-10-12

### Added

- `record_groups` input (root module, both wrappers): further records in named groups, e.g. one YAML file per team, each with `defaults` (`ttl`, `proxied`, `comment`, `tags`). Groups and `records` are merged by name and type instead of the shallow `merge()` that silently drops records; a record defined twice fails as a duplicate, and errors name the group of a record (`record_groups["mail"].records["@"]["MX"][0]`). A record's own value wins over the group default, which wins over the module default. The group name is not a part of the record keys, so moving records between groups keeps them in the state. `records` now defaults to `{}` `records` and `record_groups` can be left out (they default to `{}`), but an explicit `null` (an emptied YAML file) fails at `plan` instead of deleting the records
- `owned_names` input (root module, both wrappers): the part of the zone a module call manages (`include` and `exclude` names and everything below them, by whole labels). Configured records outside it fail at `plan`, and `report_unmanaged` only reports records inside it
- `unmanaged_ignore` and `unmanaged_policy` inputs (root module, v5 wrapper): leave expected records out of the report of unmanaged records (by a regular expression of the name and by type, e.g. the TXT ownership records of external-dns), and stop the plan instead of the warning with `unmanaged_policy = "error"`
- Service parameters of `HTTPS` and `SVCB` records as fields of `data` (`mandatory`, `alpn`, `port`, `ipv4hint`, `ech`, `ipv6hint`), checked at `plan` and written into `value` in the order of their keys; `value` as text still works, but not together with the fields. The same record written in both forms (or with and without the trailing dot of `target`) is reported as a duplicate at `plan`
- Ranges of the numeric fields of `data` are checked at `plan`: priorities, weights, ports, key tags, NAPTR order and preference (0 to 65535), TLSA, SMIMEA and SSHFP fields and algorithms (0 to 255), LOC coordinates, altitude, size and precisions and their directions, and CAA `flags` (0 to 255). The JSON Schema has the same ranges
- A warning for attributes that do not apply to the type of a record and are ignored: `content` of a record with `data`, `priority` other than on `MX` and `URI`, `tag` and `flags` other than on `CAA`. They will fail from 3.0
- The `records` output has `zone_id`, `fqdn` (fully qualified, from the configuration, known at `plan`), `ttl`, `proxied`, `priority` and `data`, for modules that use the managed names
- `modules/dns/idna` submodule: the root module for names in Unicode. It converts `zone_name` (also a looked-up one, which Cloudflare returns in Unicode), names, prefixes of record types, `ALIASES` and the targets of `CNAME`, `MX`, `NS`, `PTR`, `SRV`, `HTTPS`, `SVCB`, `NAPTR` and `URI` records, `allowed_cname_conflicts` and `owned_names` to Punycode with `provider::idna::to_ascii` of the `5xxeu/idna` provider, then calls the v5 wrapper. Only values with non-ASCII characters are converted, so keys of ASCII names stay as written, and the records have the addresses of the root module: switching `source` needs no `moved` blocks. The root module does not depend on the provider
- `modules/dns/compile` submodule: the checks of the wrappers without a provider and without resources, returning the records as the wrappers would create them, for `terraform test` of a configuration without Cloudflare credentials
- `tools/plan-guard.py`: a best-effort check of a saved plan (`terraform show -json`) that fails when it deletes or replaces records, turns off the proxy of a record (also through a new key, another record type, a renamed record or new content of an unproxied record on the same name, and through an unproxied record with the value of a proxied one on another name) or leaves a required record set (`--require @:MX`, `--zone-id` for plans with several zones) empty, unless allowed
- `tools/zone-to-ezdns.py`: writes the records of an existing zone (the response of the Cloudflare API) as an ezdns YAML file, with quoted values, keys for records that would collide, and a report of skipped records and copies
- README: "Records in Several Files", "Changing Values Without a Gap" (why `create_before_destroy` does not help, and how to rotate values with a `key` or in steps), "The Part of the Zone a Module Call Owns", "Writing the Configuration of an Existing Zone", "Checking Plans Before Apply", "Testing Your Records" and "Stability"; the examples show what they produce (plans, records, errors and warnings, the output of the tools), use addresses of the documentation ranges and the version 2.13.0, and records in YAML have a sample file

### Changed

- **Values of `data` fields out of range now fail at `plan`** (see "To 2.13" in [docs/upgrading.md](docs/upgrading.md)); the Cloudflare API rejected them at apply before
- The lookups of `import_existing` and `report_unmanaged` read up to 100,000 records per type instead of 10,000 (a limit of the module; the provider reads the records in pages)
- The warning about numbers in text values no longer reports attributes set to `null`
- README and examples: the module calls use the Terraform Registry source (`5xxeu/ezdns/cloudflare`) instead of a local copy, so they work as written; the local copy and the Git source stay described under Usage
- The README keeps what is needed to use the module; the longer guides moved to `docs`: recipes, importing existing records, records not in the configuration, checking plans, upgrading and testing. The README sections stay with a short summary and a link, so links to them still work. `CONTRIBUTING.md` lists the rules the code keeps (stable keys, wrappers in sync, keys known at plan, Terraform 1.8, linear work)
- `docs/examples.md`: module calls for mail (Google Workspace, Microsoft 365), websites (GitHub Pages, Netlify, Vercel), CAA, SRV and HTTPS records, several teams in one zone, moving a server and a zone shared with external-dns and cert-manager. CI plans every whole module call of the README and the docs against a mocked provider (`scripts/test-docs-examples.py`), so the examples stay valid, and checks the tables of the records they create (generated from `modules/dns/compile`)
- `docs/troubleshooting.md`: the common errors and warnings with their text, why they happen and what to do; `docs/README.md` lists the guides
- README: a Quick Start (token, configuration, plan and apply) and the permissions of the API token (Zone, DNS, Edit; Zone, Zone, Read for the zone lookup)
- CI checks the links between the Markdown files (`scripts/check-links.py`)

### Internal

- The records module takes `owned_names` and `unmanaged_ignore`, and an internal `source` attribute of records, which the wrappers set for grouped records so that errors say where a record is defined
- `scripts/check-sync.sh` also checks that the `idna` submodule has the interface of the root module, and that the wrappers and the `compile` submodule merge `record_groups` and check records with the same code, and that `compile` has the variables of the v4 wrapper except `zone_id` and `zone_name`
- CI tests the `compile` and `idna` submodules and the tools (unit tests, and the YAML that `zone-to-ezdns.py` writes from a fixture through the module); the full release archive contains `tools`, both archives contain `docs`
- The end-to-end test creates and imports an `HTTPS` record with service parameters as fields, so that the value the module writes is checked against the form Cloudflare stores

## [2.12.2] - 2026-10-11

### Added

- README: "Internationalized Names", how to keep names such as `münchen.de` readable in the configuration with `provider::idna::to_ascii` of the [`5xxeu/idna`](https://registry.terraform.io/providers/5xxeu/idna/latest) provider (zone name, record names and targets; record keys stay the same as with names written in Punycode in lower case)

### Changed

- The errors for a zone name that is not in Punycode (the `zone_name` validation and the zone lookup) mention `provider::idna::to_ascii`

## [2.12.1] - 2026-10-10

### Changed

- The repository moved to [5xxeu/terraform-cloudflare-ezdns](https://github.com/5xxeu/terraform-cloudflare-ezdns) (with all earlier tags), and the module is published on the Terraform Registry again, as `5xxeu/ezdns/cloudflare`. The README describes the Registry source and switching `source` from the old repository or from `NikitaPuglachenko/easy-dns/cloudflare`; the module itself is unchanged, so no addresses in the state change. Releases up to 2.12.0 stay in `i386dev/terraform-cloudflare-easy-dns`
- Release archives are named `terraform-cloudflare-ezdns-<version>.tar.gz` and `terraform-cloudflare-ezdns-v5-<version>.tar.gz`, and their provenance is verified with `--repo 5xxeu/terraform-cloudflare-ezdns` (see SECURITY.md)
- The `$id` of the JSON Schema points to the new repository
- The module is called ezdns: the schema title, the suggested local copy directory (`modules/ezdns`) and YAML file pattern (`*.ezdns.yaml`, `examples/yaml/records.ezdns.yaml`), and the comment that marks end-to-end test records (`ezdns-e2e`) use the new name. Existing copies and file mappings keep working

## [2.12.0] - 2026-10-04

### Added

- `report_unmanaged` input (root module, v5 wrapper): reads the records of all types in the zone (one request per type, `DNS Read` permission) and lists those that the configuration does not describe in the new `unmanaged_records` output (sensitive: the content of a proxied record is its hidden origin address; read it from a saved plan) and a `plan` warning with the type, name and ID of each (the first 50); without `import_existing`, the warning also lists configured records that match several records in the zone (type, name and IDs). For the report, an MX or URI record describes only existing records of its priority (or of an unknown one); an import candidate of another priority is still listed, since the module cannot see the import blocks. Nothing is deleted; each record can be added to `records` and adopted with an `import` block, or deleted by hand. A lookup at the 10,000 limit stops the plan, as for the import
- README: "Next to external-dns", how to share a zone with a controller that manages records at run time, and "Records Not in the Configuration"

### Internal

- The records module takes `import_existing` (default `true`): without it, existing records are only compared for the report, nothing is imported, and ambiguous matches do not stop the plan; new `unmanaged_records` output
- `scripts/check-sync.sh` allows `report_unmanaged` next to `import_existing` as variables of the v5 wrapper only, and checks that the root module passes every input to the v5 wrapper (`name = var.name`) and takes every output from it
- Tests: unmanaged records (with and without import, ambiguous matches count as matched, an extra MX next to a configured one of another priority, also when the configured one is in the zone twice, SRV with its priority in data), lookups of all record types, the output in the root module; e2e creates a record outside the module and checks that the report lists it and none of the records of the module (passed on this branch)

## [2.11.1] - 2026-10-04

### Fixed

- IPv6 addresses written in another form (`2001:0db8:0:0:0:0:0:1` for `2001:db8::1`, upper case) were not recognized as the same address: two such records passed the duplicate check (the API rejects the second), and with `import_existing` such a record did not match the existing one, which Cloudflare stores in the canonical form. Addresses are now compared in the canonical form (RFC 5952; IPv4-mapped addresses as `::ffff:192.0.2.1`) and sent in it; keys keep the address as written, so no state address changes. A record written in another form may get a one-time in-place update of its content to the canonical form
- With `import_existing`, a TXT value with `" "` inside (`prefix" "suffix`) matched an existing record without it (`prefixsuffix`), since every `" "` was removed before comparing. Only values in the zone file form (one or more quoted chunks, with no escapes other than `\"` and `\\`) are now joined from their chunks and unescaped, and values without a leading quote are compared as written; a value with a leading quote in another form (such as `"\065"`, a decimal escape) only matches the same text, never a decoded value

### Internal

- Tests: an IPv6 address in two forms (duplicate), sent in the canonical form (core, both wrappers), an IPv4-mapped address, import of an address in another form, TXT with `" "` inside (no false match, same value matches), quoted chunks with escaped quotes and backslashes, a decimal escape (`\065`) compared exactly, a quoted value in another form never matching a decoded one (both directions), IPv4-mapped addresses in two forms
- The end-to-end fixture writes its AAAA records in a non-canonical form (also an IPv4-mapped address in hex), to check against the API that it causes no drift and is matched on import (passed on this branch)
- The lookup limit of `import_existing` still has no automated test: the mocked provider cannot return the nested `result` list of `cloudflare_dns_records`

## [2.11.0] - 2026-10-04

### Changed

- **With `import_existing`, an ambiguous or incomplete import stops the plan** instead of showing a warning. An ambiguous match (several identical records in the zone, or records that differ only in priority without an existing record of the same priority) used to plan the record as created, which the API rejects at apply or which leaves two copies of it; a lookup that returned 10,000 records (the limit) used to miss the records beyond it. The plan now fails with the list of records (or the record type) and what to do: remove the duplicates from the zone, give the records distinct values or priorities, or set `import_existing = false` and use `import` blocks for these records. Configurations without such records are not affected. The `import_duplicates` output stays, with the same content

### Added

- With `import_existing`, a record with a priority (MX, URI) that matches several existing records takes the one with its priority: a zone with MX 10 and MX 20 on one host and the configuration with both now imports both (before, neither was imported)

### Internal

- Tests: ambiguous matches stop the plan (identical records in the zone, the same priority twice, no record of the configured priority), several matches resolved by priority; the lookup limit was checked against a real zone with the limit lowered to 1 (the plan stops, and the saved plan is not applyable)

## [2.10.4] - 2026-10-04

### Fixed

- With `import_existing`, one existing record could be imported into two addresses: configured records that differ only in `priority` (MX `primary` and `backup` with the same server) both matched the one MX record in the zone, and both got its ID. An existing record now goes to one address only: to the record with the same priority, while the others are created; without such a record, none of them is imported, and they are listed in `import_duplicates` with the plan warning
- Fractional TTLs (`ttl = 60.5`, `default_ttl = 3600.5`) and priorities passed the validation, which the JSON schema rejects; TTLs and priorities must now be whole numbers, priorities from 0 to 65535 (also in the JSON schema)
- The length of the fully qualified name was not checked: a prefix, a name and the zone that are valid on their own could combine into more than 253 characters, also in the target of a prefixed `ALIASES`; such names and targets now fail at `plan`
- `tags` given as a set in HCL (`toset([false])`, `toset([123])`) skipped the checks for booleans and numbers, which looked tags up by index

### Changed

- The release workflow builds the archives and the GitHub release only after CI passed for the tagged commit (it waits for a CI run that is still in progress); the tag itself is available to Git sources as soon as it is pushed

### Internal

- Tests: one existing record and records that differ in priority (matching, other and unknown priority), fractional TTL, `default_ttl` and priority, priority over 16 bits, names of 253 and 267 characters and an alias target of 267, sets of tags; schema parity documents for fractional TTL and priority, priorities out of range and a name over 253 characters

## [2.10.3] - 2026-10-04

### Fixed

- Internationalized zones: Cloudflare returns the name of such a zone in Unicode (`münchen.de`), while record names come back in Punycode, so a zone looked up by `zone_id` failed at `plan` with "The zone name must be a DNS name". The lookup now fails with a message to set `zone_name` in Punycode (`xn--mnchen-3ya.de`), and the error for a non-ASCII `zone_name` added in 2.10.2 no longer suggests leaving it unset (root module and both wrappers)
- Unquoted YAML booleans in `tags` and in the fields of `data` (`value: off`, `tags: [yes]`) were sent as `"false"` and `"true"`; they are now rejected like in `content`, `key`, `comment` and `tag`. In YAML, quote them. The unquoted `N` of a LOC `lat_direction` is still accepted
- Unquoted YAML numbers in `tags` and in the text fields of `data` (`digest: 0123` is sent as `"123"`) now show the same warning as in `content`, `key`, `comment` and `tag`; numeric fields such as `port` or `priority` may still be numbers
- An explicit `null` for `default_ttl`, `default_proxied` or `default_tags` failed with unclear errors; `null` now means the default (root module, both wrappers)
- With `import_existing`, the `target` of URI records was compared case-insensitively, so a record could be matched to one whose path differs only in case; it is now compared exactly
- A null `MX` (`"."`) with a priority other than 0 was accepted; RFC 7505 defines it with preference 0, and the module and the JSON schema now require it

### Changed

- README: internationalized zones need `zone_name` in Punycode; the record address in Record Keys is the one of the root module; "DNS name" instead of "hostname" in the validation rules, as in the errors; `key` must be non-empty; the two paragraphs about YAML booleans are merged; `null` defaults

### Internal

- CI checks the SHA256 of the downloaded `terraform-docs`
- `scripts/check-sync.sh` compares all variables of the v4 and v5 wrappers (except `import_existing`) and their check of text values, not only `records`
- Tests: Unicode and Punycode zone names (lookup and core), booleans and numbers in `data` and `tags`, the unquoted `N` of LOC, `null` defaults, null `MX` priority, exact URI target in import matching; schema parity documents for null `MX`, booleans in `data` and `tags`

## [2.10.2] - 2026-10-04

### Fixed

- A `zone_name` with non-ASCII characters (`münchen.de`) failed with the general "must be the DNS name of the zone" error; it now gets its own error that asks for Punycode (`xn--mnchen-3ya.de`) or an unset `zone_name` (root module and both wrappers)

### Changed

- README: `zone_name` must also be given in Punycode
- README: rewriting a record name in another form (`www` to `www.example.com`, `WWW` to `www`) changes its key and recreates the record unless a `moved` block keeps it

### Internal

- Tests: a Unicode `zone_name` in the root module and both wrappers

## [2.10.1] - 2026-10-03

### Fixed

- A `zone_name` with a trailing dot (`"example.com."`, as in zone files) broke the fully qualified names used by the checks and by import matching (`app.example.com` was taken for `app.example.com.example.com.`, so it was not found in the zone and not compared with `app`), and alias targets got the dot (`example.com.`); the trailing dot is now ignored. Record names sent to Cloudflare were not affected; an alias created with such a `zone_name` gets a one-time in-place update of its target
- An empty `zone_name` failed with an unclear error in `coalesce()`; `zone_name` is now validated as a DNS name (root module and both wrappers)
- `allowed_cname_conflicts` accepted any string, and a misspelled name never matched; the names are now validated like the names in `records`

### Added

- With `import_existing`, `plan` warns when the lookup of a record type returns 10,000 records (the limit): records beyond it are not found and would be planned as new

### Internal

- Tests: zone names with a trailing dot and in another case, empty and invalid zone names, invalid and fully qualified `allowed_cname_conflicts`, one lookup per record type with `import_existing`

## [2.10.0] - 2026-10-03

### Changed

- Validation errors of `records` list every record that fails, with its path and value: `records["app"]["CAA"][0]: tag "isue"`, `records["_sip._tcp"]["SRV"][0].data: missing field "port"`, `records["web"]["CNAME"][0]: "192.0.2.1"`; before, the message only named the rule
- The JSON Schema checks hostnames like the module: `content` of `CNAME`, `MX`, `NS` and `PTR` records and `target`/`replacement` of `SRV`, `HTTPS`, `SVCB` and `NAPTR` records (labels, at most 253 characters, not an IP address; `@`, and `.` where the module allows it). Editors now flag such values before `plan`
- README: when not to use the module

### Internal

- The core module is split into `names.tf`, `keys.tf` and `checks.tf`, with an overview in `main.tf`
- Tests of record identity (reordering keeps keys, `key` keeps the address when the value changes, keys are case-sensitive, YAML and HCL give the same records), TTL boundaries, wildcard positions, names with a trailing dot and Punycode
- `scripts/test-schema.py --terraform` runs the schema test documents through the module, so the schema and the validation must accept and reject the same documents; CI runs it
- The end-to-end test checks that imported and migrated records keep their Cloudflare IDs

## [2.9.0] - 2026-10-03

### Added

- `import_duplicates` output (root module, v5 wrapper): records that match several existing records in the zone when `import_existing` is set, keyed by record key, with the Cloudflare IDs of the matches. These records are not imported, and `plan` shows a warning listing them
- Release archives have signed build provenance (`gh attestation verify <archive> --repo i386dev/terraform-cloudflare-easy-dns --signer-workflow i386dev/terraform-cloudflare-easy-dns/.github/workflows/release.yml`)

### Changed

- `target` of `SRV`, `HTTPS` and `SVCB` records and `replacement` of `NAPTR` records are validated as hostnames, like `CNAME`, `MX`, `NS` and `PTR` values, or `.`; values with spaces, invalid characters, an IP address or `@` fail at `plan` instead of at the Cloudflare API

## [2.8.2] - 2026-10-03

### Fixed

- A wildcard could end up outside the leftmost label when names combine: a prefix under a wildcard base name (`"_acme-challenge.TXT"` under `"*"` gave `_acme-challenge.*`, `"x.A"` under `"*.app"` gave `x.*.app`) and the target of `<prefix>.ALIASES` under a wildcard base name; such names now fail at `plan`
- A `CNAME` or alias pointing to its own name (`"app" = { ALIASES = [{ content = "app" }] }`, `www CNAME www.example.com.`, `@ CNAME @`) fails at `plan`
- A `default_ttl` below `minimum_ttl` fails at `plan` also when no record uses it

### Changed

- Error messages say "DNS name" instead of "hostname" for `CNAME`, `MX`, `NS` and `PTR` values
- README: a table of the `records` keys up front; `zone_name` must match `zone_id` (the module cannot check it); when to use `key`; `import_existing` only finds IDs and reads up to 10,000 records per type; Punycode for internationalized names; `allowed_cname_conflicts` as a migration escape hatch; what the validation covers and what it leaves to the API; "Structured Records" instead of "All Record Types"

## [2.8.1] - 2026-10-03

### Fixed

- Unquoted YAML 1.1 booleans (`off`, `on`, `yes`, `no`, `N`, `Y`) in `content`, `key`, `comment` or `tag` were turned into `"false"`/`"true"` without an error; they now fail at `plan` with the record and a hint to quote them. Numbers there (`0123` -> `"123"`, `1.10` -> `"1.1"`) show a warning

### Changed

- README: values computed by other resources need a `key`; `&depth=1` for Git sources in CI; managing a record type or field the module does not support next to the module call; quoting text values in YAML

## [2.8.0] - 2026-10-03

### Changed

- **TTLs below 60 seconds need `minimum_ttl = 30`.** The new `minimum_ttl` input (root module, both wrappers; `60` by default, `30` for Enterprise zones) is the lowest TTL other than `1` (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones, so on other plans they failed at the API; now the plan fails with what to change. Enterprise zones that use TTLs from 30 to 59 seconds must set `minimum_ttl = 30` when upgrading

### Fixed

- `ALIASES` under a fully qualified base name (`"app.example.com"`) pointed to `app.example.com.example.com`, and `"cdn.ALIASES"` to `cdn.app.example.com.example.com`; alias targets now use the same fully qualified name as every other check, so a short and a fully qualified base name give the same target. Configurations that used short base names plan no change
- Import matching (`import_existing`) did not find existing records under a fully qualified base name
- `CNAME`, `MX`, `NS` and `PTR` values are validated as hostnames (labels of letters, digits, `_` and `-`, at most 253 characters, not an IP address; `@` for the apex, `.` for a null `MX`); before, only `CNAME` was checked, and only for not being an IP address, so values with spaces or invalid characters failed at the Cloudflare API

## [2.7.0] - 2026-10-01

### Added

- `allowed_cname_conflicts` input (root module, both wrappers): names where a `CNAME` may share its name with other records, for existing zones where Cloudflare accepted it for records that are not proxied. Names are compared fully qualified and case-insensitively; only the listed names are exempt, a second `CNAME` on a name still fails, and a listed name without a conflict shows a warning
- A provider v5 release archive, `terraform-cloudflare-easy-dns-v5-<version>.tar.gz`: the root module, `modules/dns/v5` and `modules/dns/records`, without the v4 wrapper and its migration `moved` block, for copies in repositories that pin provider v5
- README: what a copy in a larger repository may replace or drop

### Fixed

- Record names are sent in lower case, as Cloudflare stores them: with provider v5, a name in another case showed a change on every plan. Keys keep the name as written, so no state address changes; with the v4 wrapper, such a record gets a one-time in-place update of its name

### Changed

- The duplicate error explains that `MX` records differing only in priority and `CAA` records differing only in flags need a `key`; the CNAME error points to `allowed_cname_conflicts`
- The `moved` block from the v4 wrapper is in `modules/dns/v5/migrate-from-v4.tf`, so a v5-only copy can leave it out

## [2.6.4] - 2026-10-01

### Fixed

- Import matching with `import_existing` no longer drops quotes inside TXT values or compares every `data` field case-insensitively, which could match a different existing record (a TXT value differing only in inner quotes, a NAPTR `regex` or a public key differing in case); hostnames and hex values are still compared case-insensitively
- Import matching treats a TXT value in the zone file form (`"v=spf1 \"a\" -all"`) as the same record as its unquoted form (`v=spf1 "a" -all`), as Cloudflare serves them identically; before, such a record was not adopted and `apply` failed with "record already exists"
- Import matching compares the issuer domain of CAA `issue`/`issuewild` values case-insensitively again (the parameters after `;` and `iodef` URLs exactly), and OPENPGPKEY keys exactly instead of lower-cased
- Two or more `CNAME`s on one name are rejected also when they have different `key`s
- The same record written with different name forms (`www` and `www.example.com`, `@` and the zone name) is rejected as a duplicate at `plan` instead of failing at `apply`; addresses and hostnames are compared case-insensitively and without a trailing dot
- The CNAME checks compare names fully qualified: a `CNAME` on the zone name is accepted next to other records like one on `@`, and `www` and `www.example.com` are the same name

## [2.6.3] - 2026-09-29

### Added

- Releases include an archive of the module (`terraform-cloudflare-easy-dns-<version>.tar.gz`, with a `VERSION` file) and `SHA256SUMS`, to keep a local copy of the module in a configuration

### Changed

- The module is not published on the Terraform Registry: the README describes a local copy of the module (without GitHub or the Registry on `terraform init`) and a Git source, and how to switch from the Registry source; the examples, the YAML schema setup (a local schema file) and the upgrade guide follow this

### Removed

- The Terraform Registry badge and the temporary Registry note

## [2.6.2] - 2026-09-27

### Changed

- README: a note that the module cannot be downloaded from the Terraform Registry as `i386dev/easy-dns/cloudflare` yet, with the Git source to use until it is republished

## [2.6.1] - 2026-09-27

### Changed

- The repository moved to [i386dev/terraform-cloudflare-easy-dns](https://github.com/i386dev/terraform-cloudflare-easy-dns) and the module to the Registry source `i386dev/easy-dns/cloudflare`; the README, examples, badges and the schema `$id` use the new addresses, and the README describes switching `source` from `NikitaPuglachenko/easy-dns/cloudflare`
- CI runs the gitleaks CLI instead of the gitleaks action, which requires a license for organizations

## [2.6.0] - 2026-09-26

### Added

- JSON Schema `schema/records.schema.json` for records kept in YAML, for completion and validation in editors; it is generated from the records module and tested in CI, also against the module through `yamldecode`
- Examples `examples/yaml` (records in `records.easy-dns.yaml`, checked by the schema in CI) and `examples/import` (adopting an existing zone)
- Unknown record attributes fail at `plan` with the record and the attribute, e.g. `records["app"]["A"][0]: unknown attribute "proxid"`, also inside `settings`; before, Terraform silently dropped them, so a misspelled optional attribute was ignored

### Fixed

- A LOC record from YAML with an unquoted `lat_direction: N` failed, since `yamldecode` reads it as `false`; it is now read as `N`

### Changed

- `examples/v5` uses the root module, like the Registry source
- README: HCL or YAML compared, links to the Cloudflare documentation of record types, `data`, `settings`, comments and tags; a table of contents, the detailed "How It Works" is now "Record Model", and the upgrade and migration guides are one section with the order of the steps and a guide for unknown attributes when upgrading to 2.6
- The `records` input of the root module and the wrappers has the type `any`, so unknown attributes reach the check; the record schema is in the input description and the README, and the records module still converts the value to the typed structure

## [2.5.3] - 2026-09-26

### Fixed

- README layout on the Terraform Registry: badges on one line, code examples narrow enough to fit without being cut off, and the state address table with short keys

## [2.5.2] - 2026-09-26

### Changed

- README: a short introduction to the input model with a minimal example and the resulting state addresses, before the full example

## [2.5.1] - 2026-09-26

### Changed

- The workarounds for provider v5 issues link to them: the per-type lookup of existing records ([#7004](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004)) and the `modified_on` error after the v4 to v5 migration ([#7387](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387)), so they can be removed once the issues are fixed

## [2.5.0] - 2026-09-26

### Added

- `default_ttl`, `default_proxied`, `default_comment` and `default_tags` inputs, overridable per record
- `comment` and `tags` per record; `settings` (`flatten_cname`, `ipv4_only`, `ipv6_only`) per record for provider v5
- Validation of IPv4 addresses in `A`, IPv6 addresses in `AAAA`, hostnames in `CNAME`, the length of `TXT` values and DNS names of base names, prefixes and `ALIASES`
- End-to-end tests against a real Cloudflare zone: every record type, drift, updates, import and the v4 to v5 migration; run weekly and on demand
- CI tests on the minimum supported provider versions
- Releases are created from the changelog when a tag is pushed
- README: badges, recipes, a deprecation note for the v4 wrapper

### Fixed

- Import failed with a Terraform crash when the zone had CAA or DNSKEY records together with other types: provider v5 returns `data.flags` with different types in one list, so existing records are now looked up per record type
- SVCB and HTTPS records showed a change on every plan: Cloudflare returns their `target` with a trailing dot, which is now added
- The v4 wrapper required provider `~> 4.30`, but `cloudflare_record` has the `content` attribute only since 4.39; the minimum is now `~> 4.41`, which also fixes the handling of `content` and `value` in the state

## [2.4.0] - 2026-09-26

### Added

- Root module wrapping the v5 wrapper, so `source = "NikitaPuglachenko/easy-dns/cloudflare"` works as shown on the Terraform Registry; the submodules are unchanged
- CI check that the root module and the wrappers have the same inputs and outputs

### Changed

- README and examples use the Terraform Registry source; links point to GitHub, so they work on the Registry page
- README describes switching from the v5 submodule to the root module with a `moved` block

## [2.3.0] - 2026-09-26

### Added

- Import of records that already exist in the zone (provider v5): `import_existing` input and `import_ids` output for an `import` block with `for_each`

## [2.2.0] - 2026-09-26

### Added

- A `CNAME` (including `ALIASES`) sharing its name with other records fails at `plan`, except at the zone apex
- Module READMEs with inputs, outputs, requirements and resources generated by terraform-docs; CI checks that they are up to date

### Changed

- Duplicate record errors show where each duplicate is defined in `records`
- The main README links to the generated reference instead of maintaining the input and output tables by hand

## [2.1.0] - 2026-09-26

### Added

- Record types `SRV`, `URI`, `HTTPS`, `SVCB`, `TLSA`, `SMIMEA`, `SSHFP`, `DS`, `DNSKEY`, `CERT`, `NAPTR` and `LOC` through the new `data` field, and `OPENPGPKEY` (provider v5)
- Validation of `data` fields for each record type
- `URI` records require `priority`

### Changed

- Wrapper tests cover only the mapping to the provider resource; record parsing is tested in the core module

## [2.0.0] - 2026-09-26

### Changed

- **Breaking:** records are keyed in the state by their content in the zone file format (`app A 30.40.50.60`, `www CNAME`, `_dmarc TXT 21541c4e7044`) instead of their position in the list, so adding, removing or reordering items no longer recreates other records. Existing states must be migrated, see "Upgrading from v1" in the README

### Added

- Optional `key` field to keep a record in place when its value changes
- Duplicate record keys fail at `plan` with the list of duplicates
- `state_migration` output mapping the 1.x keys to the new ones, used to generate `moved` blocks

## [1.1.0] - 2026-09-26

### Added

- Validation of the `records` input: supported record types, non-empty `content`, TTL range, `proxied` only for `A`/`AAAA`/`CNAME`/`ALIASES`, `priority` for `MX`, `tag` for `CAA`
- `records` output with `id`, `name`, `type` and `content` of each managed record
- Complete examples for provider v4 and v5 in `examples/`
- Tests for the core module and the examples
- Dependabot updates for GitHub Actions

### Changed

- README usage example starts with the zone apex (`@`)

## [1.0.0] - 2026-09-26

### Added

- Provider-agnostic core module `modules/dns/records`
- `modules/dns/v4` wrapper for Cloudflare provider v4 (`cloudflare_record`)
- `modules/dns/v5` wrapper for Cloudflare provider v5 (`cloudflare_dns_record`) with a `moved` block for migration from v4
- Optional `zone_name` input, looked up from `zone_id` when omitted
- Plan-only tests with a mocked provider
- CI: `terraform fmt`, `validate`, `test`, TFLint and Gitleaks

### Fixed

- The locals file was not loaded by Terraform
- Hardcoded root domain replaced with `zone_name` or a zone lookup
- Defaults for `ttl`, `proxied` and `flags` were `null` instead of the documented values
- Inline aliases pointed to a relative name instead of the full hostname
- Zone apex (`@`) handling for aliases and nested names

[Unreleased]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.19.0...HEAD
[2.19.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.18.0...v2.19.0
[2.18.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.17.0...v2.18.0
[2.17.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.16.4...v2.17.0
[2.16.4]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.16.3...v2.16.4
[2.16.3]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.16.2...v2.16.3
[2.16.2]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.16.1...v2.16.2
[2.16.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.16.0...v2.16.1
[2.16.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.15.0...v2.16.0
[2.15.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.14.1...v2.15.0
[2.14.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.14.0...v2.14.1
[2.14.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.13.1...v2.14.0
[2.13.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.13.0...v2.13.1
[2.13.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.12.2...v2.13.0
[2.12.2]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.12.1...v2.12.2
[2.12.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.12.0...v2.12.1
[2.12.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.11.1...v2.12.0
[2.11.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.11.0...v2.11.1
[2.11.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.10.4...v2.11.0
[2.10.4]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.10.3...v2.10.4
[2.10.3]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.10.2...v2.10.3
[2.10.2]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.10.1...v2.10.2
[2.10.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.10.0...v2.10.1
[2.10.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.9.0...v2.10.0
[2.9.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.8.2...v2.9.0
[2.8.2]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.8.1...v2.8.2
[2.8.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.8.0...v2.8.1
[2.8.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.6.4...v2.7.0
[2.6.4]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.6.3...v2.6.4
[2.6.3]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.6.2...v2.6.3
[2.6.2]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.6.1...v2.6.2
[2.6.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.6.0...v2.6.1
[2.6.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.5.3...v2.6.0
[2.5.3]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.5.2...v2.5.3
[2.5.2]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.5.1...v2.5.2
[2.5.1]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.5.0...v2.5.1
[2.5.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/5xxeu/terraform-cloudflare-ezdns/releases/tag/v1.0.0
