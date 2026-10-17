# Testing

Part of the documentation of [ezdns](../README.md).

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

Plan time grows a little faster than the number of records. Measured on 2026-10-13 with Terraform 1.16.4, the root module and a mocked provider (`terraform test`, `command = plan`) on an Apple M2 Pro: 1,000 records (A, AAAA, CNAME, TXT and MX in equal parts) take about 8 seconds, 5,000 records about 55 seconds. A real plan adds the refresh of every record by the provider.

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
  version = "2.15.0"

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

1. Creates records of every type through the root module and checks that a second `plan` shows no changes (no drift in the provider).
2. Changes values: a record without a `key` is replaced, a record with a `key` is updated in place.
3. Adopts the same records into an empty state with `import_existing` and checks that all of them are imported, none created, and each one under the ID of the record created in step 1.
4. Creates records with the v4 wrapper and opens the state with the v5 wrapper: the records must be moved, not recreated, and keep their keys and Cloudflare IDs.
5. Deletes everything. `tests/e2e/sweep.sh` also removes records left by failed runs; it only deletes records with the comment `ezdns-e2e` and a run label in the name.

```sh
CLOUDFLARE_API_TOKEN=... E2E_ZONE_ID=... E2E_ZONE_NAME=example.com tests/e2e/run.sh
```

The token needs the `DNS Edit` permission on the zone. In CI, the test runs weekly and on demand (never for pull requests), with the token stored in the `cloudflare-e2e` environment.
