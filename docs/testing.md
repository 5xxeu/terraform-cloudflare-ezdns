# Testing

Part of the documentation of [ezdns](../README.md).

The core module, both wrappers and the examples have Terraform tests (the wrappers and examples use a mocked provider), no Cloudflare credentials needed. The core module's tests also pin the invariants of name normalization (`names.tftest.hcl`: every form of a name gives one fully qualified name) and record identity (`identity.tftest.hcl`: reordering records keeps their keys, a `key` keeps the address when the value changes, YAML and HCL give the same records). The v5 wrapper adds identity tests with applied mock state in `modules/dns/v5/tests/identity.tftest.hcl`: reordering, moving records between groups or between a group and `records`, and changing a value under the same key keep the addresses and IDs:

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

CI runs `terraform fmt`, `validate` and `test` for the root module, the core module, the `compile` and `idna` submodules, both wrappers and the examples (on Terraform 1.8.0 and the latest version, and on the minimum supported provider versions), checks that the module READMEs and the JSON Schema are up to date, tests the schema and the tools, checks that the root module, the wrappers and the submodules have the same interface, [TFLint](https://github.com/terraform-linters/tflint) and [Gitleaks](https://github.com/gitleaks/gitleaks) on every pull request. The Benchmarks check measures the core on pull requests that change it and on pushes to main, and blocks time or peak memory regressions over 2x the stored CI baseline.

## Benchmarks

Plan time grows a little faster than the number of records. Measured on 2026-10-13 with Terraform 1.16.4, the root module and a mocked provider (`terraform test`, `command = plan`) on an Apple M2 Pro: 1,000 records (A, AAAA, CNAME, TXT and MX in equal parts) take about 8 seconds, 5,000 records about 55 seconds. A real plan adds the refresh of every record by the provider.

`tests/bench/plain` measures plain records through the records module, without groups, import or a provider: `hosts` names (default 500) with an A, an AAAA, a TXT and an MX record each, plus `hosts` separate CNAME names. The five types have equal counts:

```sh
terraform -chdir=tests/bench/plain init
time terraform -chdir=tests/bench/plain plan
```

`import_existing` and `report_unmanaged` compare the configured records with the records of the zone. `tests/bench/import` measures that part on the core module, without a provider: `hosts` hosts (default 1,000) with an A, a TXT and an MX record each, a zone with the same records, half of the A records with another value, and a stray record per host:

```sh
terraform -chdir=tests/bench/import init
time terraform -chdir=tests/bench/import plan -var hosts=1000
```

Measured on 2026-10-18 with Terraform 1.16.4 on an Apple M2 Pro: 1,000 hosts (3,000 configured and 4,000 existing records) take about 7 seconds, 500 hosts about 3 seconds, and the time grows linearly. Up to 2.14.0 the comparison was quadratic: 500 hosts took 65 seconds, 1,000 hosts more than 4 minutes.

`tests/bench/groups` measures the merge of `record_groups` and the checks of the records on the `compile` module: `hosts` names (default 1,000, at most 1,024) with an A record each, `groups` groups (default 10) with a TXT record on `hosts` names each, half of them also in `records`, and a CNAME conflict, listed in `allowed_cname_conflicts`, on every tenth name:

```sh
terraform -chdir=tests/bench/groups init
time terraform -chdir=tests/bench/groups plan -var hosts=1000
```

Measured on 2026-10-18 with Terraform 1.16.4 on an Apple M2 Pro: 1,000 hosts (11,100 records) take about 37 seconds, 500 hosts about 16 seconds, 250 hosts about 8 seconds. Up to 2.15.0 the time was quadratic: 17, 55 and 203 seconds.

`scripts/bench.py` runs three plans per workload (`--runs N`), after a quiet init, with fixed CI sizes: plain with 500 hosts, groups with 500 hosts and 10 groups, and import with 1,000 hosts. It records the Terraform version, variables, the number of runs and the median wall time and median peak memory of the plan process (each metric separately, so one slow run on a busy runner does not fail the check), then compares time and memory with `tests/bench/baseline.json`. Either measurement more than 2x the baseline fails the check. Missing workloads or different sizes warn and skip comparison; a different Terraform version warns. There is no measurement history.

```sh
python3 scripts/bench.py
python3 scripts/bench.py --json results.json
python3 scripts/bench.py --summary summary.md
python3 scripts/bench.py --only plain   # repeat --only to select several workloads
python3 scripts/bench.py --runs 1       # one plan per workload, faster
python3 scripts/bench.py --baseline results.json --factor 2
python3 scripts/bench.py --update
```

CI uses Terraform 1.16.4 on `ubuntu-latest`. On pull requests the Benchmarks job always runs, but only measures plans when the diff from the merge base with the base branch touches any root `.tf` file, Terraform files under `modules`, `tests/bench` or `scripts/bench.py`. Otherwise it reports "no core changes". Pushes to main always measure plans. The job writes a step summary and uploads `bench-results.json` in the `bench-results` artifact, including when a comparison fails.

The baseline was measured by the CI job on `ubuntu-latest` with Terraform 1.16.4 on 2026-10-20: plain took about 8 seconds and 174.72 MiB peak memory, groups about 23 seconds and 312.96 MiB, and import about 9 seconds and 244.18 MiB. Update it from the JSON artifact of a CI run, or use `--update` on the runner, then commit it. Update it when changing the workloads, sizes, Terraform version or runner. `--update` replaces the baseline with the current run's results; with `--only`, it updates the measured workloads and keeps the others. Both forms set the Terraform version and platform from the current run. Local measurements are useful for investigating changes, but should not replace the CI baseline. An accepted slowdown needs an explanation in the pull request of the added work and why its cost is justified, then a reviewed baseline update from that CI run.

To find the slow part of a plan, write a trace log and list the slowest locals, validations, outputs and checks:

```sh
TF_LOG=trace TF_LOG_PATH=trace.log terraform -chdir=tests/bench/groups plan -var hosts=500
python3 tests/bench/profile.py trace.log
```

## Testing Your Records

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
  version = "2.18.0"

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

## End-to-End Tests

`tests/e2e/run.sh` runs against a real Cloudflare zone. Under a label of the run (e.g. `e2e-1234.example.com`), it:

1. Before the records exist, adds an `A` record through the API on the name of `A` records that the plan creates: the report takes it as an old value and the plan passes with `unmanaged_policy = "error"`, while `tools/plan-guard.py --unmanaged` lists it (the record is deleted again). Then creates records of every type through the root module, some of them in `record_groups` with a TTL default of the group, and checks that a second `plan` shows no changes (no drift in the provider).
2. Changes values: a record without a `key` is replaced, a record with a `key` is updated in place. With `report_unmanaged` and `unmanaged_policy = "error"` (limited to the label with `owned_names`, since the zone has records of other runs) the plan of the change passes; `plan-guard --unmanaged` passes on that plan, as the old values are in the state. A record created through the API under the label is then reported, stops the plan with `"error"`, and is listed by `plan-guard --unmanaged`, with none of the records of the module. Records with `ignore_changes` keep values changed through the API.
3. Adopts the same records into an empty state with `import_existing` and checks that all of them are imported, none created, and each one under the ID of the record created in step 1.
4. Creates records with the v4 wrapper and opens the state with the v5 wrapper: the records must be moved, not recreated, and keep their keys and Cloudflare IDs.
5. Creates records with names, a prefix of a record type and a `CNAME` target in Unicode through the `idna` submodule, and checks that they are stored in Punycode without drift.
6. Applies a small configuration from the highest stable ancestor tag before the current commit (or `E2E_UPGRADE_FROM`), then switches to the current checkout. The saved plan must have no record creates or deletes; moves and in-place updates are reported. After apply, record keys and Cloudflare IDs must match and the next plan must show no changes. Tags and their commits must be available locally.
7. Deletes everything. `tests/e2e/sweep.sh` also removes records left by failed runs; it only deletes records with the comment `ezdns-e2e` and a run label in the name.

The log of a run names neither the zone nor the records, since the CI logs are public; in CI the zone name is a secret of the environment, so GitHub masks it.

```sh
CLOUDFLARE_API_TOKEN=... E2E_ZONE_ID=... E2E_ZONE_NAME=example.com tests/e2e/run.sh
```

The token needs the `DNS Edit` permission on the zone. In CI, the test runs weekly and on demand (never for pull requests), with the token and the zone name stored in the `cloudflare-e2e` environment, which only the `main` branch can use.
