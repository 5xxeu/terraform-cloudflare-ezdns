# Contributing

Bug reports, questions and pull requests are welcome. For a larger change (a new input, record type or behavior), open an issue first, so we can agree on the design before you write the code.

Security problems are reported privately, see [SECURITY.md](SECURITY.md).

## Development Setup

- Terraform 1.9.0 or later (CI tests 1.9.0 and the latest version)
- [terraform-docs](https://terraform-docs.io) v0.24.0
- [TFLint](https://github.com/terraform-linters/tflint)
- Python 3 with `jsonschema` and `pyyaml`
- `shellcheck`, `jq`

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
docs/          # The guides: record model, validation, inputs and outputs, YAML, examples, ...
scripts/       # The checks of CI
tests/         # terraform test with a mocked provider, the end-to-end test, benchmarks
```

Both wrappers share the same inputs (except the v5-only ones), outputs and record keys, so switching between them only requires changing the `source`. The root module passes everything to the v5 wrapper, so it has the same inputs and outputs. The v4 wrapper is supported in 3.x as long as Cloudflare releases provider v4 versions, see [Stability](README.md#stability): a change of the core goes into both wrappers, and CI tests the v4 wrapper on the minimum provider 4.41.0 and the latest 4.x.

The README covers what the module does and how to start; the record model, validation, inputs and outputs and the longer guides are in [docs](docs).

## Checks

Run the same checks as CI before you open a pull request:

```sh
terraform fmt -recursive
./scripts/check-sync.sh        # the root module and the wrappers have the same interface
./scripts/generate-docs.sh     # after changing variables, outputs or requirements
python3 scripts/generate-schema.py
python3 scripts/test-schema.py --terraform
python3 scripts/test-docs-examples.py   # every module call in the README and docs plans,
                                        # and the tables of their records match (--write updates them)
python3 scripts/check-versions.py       # current version references, including example comments
python3 scripts/test-zone-converter.py  # equivalent zone values through compile, both key modes
python3 scripts/test-plan-checks.py     # input checks fail at plan also with values known after apply
python3 scripts/check-links.py          # links between the Markdown files
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"

# in the changed module and its examples
terraform init -backend=false && terraform validate && terraform test
# or in every directory that CI tests, with a given Terraform binary (CI tests 1.9.0 too)
./scripts/test-modules.sh [path/to/terraform]
```

The plan-only tests use a mocked provider and need no Cloudflare credentials, see [Testing](docs/testing.md). The end-to-end test needs a real zone; it runs weekly in CI, so you do not have to run it, but say in the pull request if your change affects how records are created, imported or migrated.

## Pull Requests

- Keep one change per pull request, with tests for new behavior and fixed bugs.
- Keep the copies of the interface in sync: a change of inputs or outputs goes into `modules/dns/v5`, `modules/dns/idna` and the root module.
- Changing a record key moves records in the state of every user. Avoid it, or add `moved` blocks and a note in [Upgrading and Migration](docs/upgrading.md).
- Add a line to the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md) for changes users see.
- Update the README or the guide in `docs` when the behavior or the inputs change.

## Rules the Code Keeps

These are not visible from a single file, and the tests catch only some of them:

- **Record keys stay the same within 2.x.** A key is the address of a record in the state of every user; a change of the key format recreates records. Changes of keys wait for 3.0 and come with `moved` blocks.
- **The wrappers and compile are one code.** `modules/dns/v4`, `modules/dns/v5` and `modules/dns/compile` share their inputs, which `scripts/check-sync.sh` compares, and both pass `records` and `record_groups` through `modules/dns/prepare` (the merge of `record_groups` and the checks of the values as given) to `modules/dns/records`, and its records through `modules/dns/checks` (the checks over all records) to the resources; the root module passes every input to the v5 wrapper.
- **Keys stay known at plan.** A value known only after apply (a TTL or a target from another resource) must not make names or keys unknown, or `for_each` fails. So there is no `try()` over record values: `try()` returns an unknown result for a value that is not wholly known. Use `can()` over the shape (names, types and attribute names) and conditionals. The `computed_values` tests of `modules/dns/prepare`, `modules/dns/v5` and `modules/dns/idna` and `scripts/test-plan-checks.py` cover it.
- **Validations and the order of apply.** A variable validation can refer to other variables of its module, but not to a local built from its own variable, even through other locals: Terraform reports a cycle. So `modules/dns/records` builds the lists of problems over all records (`output.diagnostics`) and `modules/dns/checks` validates them, one input per check. A validation whose value is known only after apply waits for apply, and an output that passes data on beside the validated inputs does not wait for it: the `flat_records` output of `modules/dns/checks` has `depends_on` on every checked input, so the records are not applied before a failing check (`scripts/test-plan-checks.py` applies a saved plan and reads the state). On Terraform 1.9.0 a failing validation of a constant argument whose message refers to another variable shows "Failed to evaluate condition error message" instead of the message; the wrappers pass outputs of the records module, which do not hit it.
- **The work grows linearly with the records.** Do not scan all records once per name (a lookup per name in a map grouped once instead); plans of zones with thousands of records must stay fast. Some functions scan their whole argument on every call: `contains()` inside a loop over records (look up a map built once instead), `distinct()` on a long list (`toset()`), and `alltrue(flatten(...))` over all records (nest `alltrue()` per level). `tests/bench` has plain, groups and import benchmarks and a profile of the trace log. `python3 scripts/bench.py` runs the workloads; CI checks core changes against a stored runner baseline and fails above 2x time or peak memory, see [Testing](docs/testing.md).
- **Checks fail early and name the record.** A value the API would reject fails at `plan` with the path of the record (`records["www"]["A"][0]`).
- **`tools` use the Python standard library only**, exit with 0 (passed), 1 (failed, or written with notes) or 2 (the input or the arguments are wrong), and `plan-guard.py` fails rather than passes when it cannot tell.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By taking part, you agree to follow it.
