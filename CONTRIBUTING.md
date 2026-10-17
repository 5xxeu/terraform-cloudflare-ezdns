# Contributing

Bug reports, questions and pull requests are welcome. For a larger change (a new input, record type or behavior), open an issue first, so we can agree on the design before you write the code.

Security problems are reported privately, see [SECURITY.md](SECURITY.md).

## Development Setup

- Terraform 1.8.5 or later (CI tests 1.8.5 and the latest version)
- [terraform-docs](https://terraform-docs.io) v0.24.0
- [TFLint](https://github.com/terraform-linters/tflint)
- Python 3 with `jsonschema` and `pyyaml`
- `shellcheck`, `jq`

The [Structure](README.md#structure) section of the README shows where the code lives. In short: the record logic is in `modules/dns/records`, the provider wrappers in `modules/dns/v4` and `modules/dns/v5`, and the root module passes everything to the v5 wrapper. `modules/dns/compile` gives the records without a provider, `modules/dns/idna` converts names in Unicode before the v5 wrapper, and `tools` has the Python scripts (`plan-guard.py`, `zone-to-ezdns.py`). The README covers the use of the module; the longer guides (recipes, import, unmanaged records, plan checks, upgrading, testing) are in [docs](docs).

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
python3 scripts/check-links.py          # links between the Markdown files
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"

# in the changed module and its examples
terraform init -backend=false && terraform validate && terraform test
# or in every directory that CI tests, with a given Terraform binary (CI tests 1.8.5 too)
./scripts/test-modules.sh [path/to/terraform]
```

The plan-only tests use a mocked provider and need no Cloudflare credentials, see [Testing](docs/testing.md). The end-to-end test needs a real zone; it runs weekly in CI, so you do not have to run it, but say in the pull request if your change affects how records are created, imported or migrated.

## Pull Requests

- Keep one change per pull request, with tests for new behavior and fixed bugs.
- Keep the wrappers in sync: a change of inputs or outputs goes into `modules/dns/v4`, `modules/dns/v5` and the root module.
- Changing a record key moves records in the state of every user. Avoid it, or add `moved` blocks and a note in [Upgrading and Migration](docs/upgrading.md).
- Add a line to the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md) for changes users see.
- Update the README (or the guide in `docs`) when the behavior or the inputs change.

## Rules the Code Keeps

These are not visible from a single file, and the tests catch only some of them:

- **Record keys stay the same within 2.x.** A key is the address of a record in the state of every user; a change of the key format recreates records. Changes of keys wait for 3.0 and come with `moved` blocks.
- **The wrappers are one code.** `modules/dns/v4`, `modules/dns/v5` and `modules/dns/compile` share their inputs and the merge of `record_groups`; `scripts/check-sync.sh` compares them, and the root module passes every input to the v5 wrapper.
- **Keys stay known at plan.** A value known only after apply (a TTL or a target from another resource) must not make names or keys unknown, or `for_each` fails. So there is no `try()` over record values: `try()` returns an unknown result for a value that is not wholly known. Use `can()` over the shape (names, types and attribute names) and conditionals. The `computed_values` tests of `modules/dns/v5` and `modules/dns/idna` cover it.
- **Terraform 1.8.** Variable validations cannot reference other variables, so checks across inputs are preconditions of outputs or `check` blocks; provider functions need 1.8.
- **The work grows linearly with the records.** Do not scan all records once per name (a lookup per name in a map grouped once instead); plans of zones with thousands of records must stay fast. Some functions scan their whole argument on every call: `contains()` inside a loop over records (look up a map built once instead), `distinct()` on a long list (`toset()`), and `alltrue(flatten(...))` over all records (nest `alltrue()` per level). `tests/bench` has benchmarks and a profile of the trace log, see [Testing](docs/testing.md).
- **Checks fail early and name the record.** A value the API would reject fails at `plan` with the path of the record (`records["www"]["A"][0]`).
- **`tools` use the Python standard library only**, exit with 0 (passed), 1 (failed, or written with notes) or 2 (the input or the arguments are wrong), and `plan-guard.py` fails rather than passes when it cannot tell.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By taking part, you agree to follow it.
