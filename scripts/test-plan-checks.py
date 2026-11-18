#!/usr/bin/env python3
"""Check the input checks of records with values known only after apply, and the checks
over all records as a caller sees them.

A check of an input fails at plan when the values it looks at are known, and is put off
until apply when they are not; the keys of records with a key stay known at plan.
terraform test cannot expect a failure in a called module, so these cases are planned
(and some applied) here:

- through compile, which needs no provider: a terraform_data with for_each over its
  records stands for the resources of the wrappers, whose keys must be known at plan.
  The checks over all records (modules/dns/checks) are planned with plan -out, the saved
  plan is applied, and the state is read: a check put off until apply must fail before
  any of these resources is created or changed;
- through modules/dns/checks alone, for the full text of the messages that take the
  context of the call (minimum_ttl, owned_names);
- through the v4 wrapper (provider v4), the v5 wrapper and the root module, with terraform test and a mock provider (no
  Cloudflare account): each run must fail with the message of its check;
- the plan JSON of root, v5, v4, idna and compile (made-up token, nothing is read from
  Cloudflare): the records output is sensitive and record_metadata is not;
- the v4 wrapper with a zone and a content known only after apply (plan only): the keys of
  the records stay known at plan;
- the command of docs/upgrading.md that writes moved blocks from state_migration, on the
  addresses of the records (root, v5, v4 as a submodule and as a module "v4", idna), against a state with the 2.x keys.

The cases are in scripts/plan_checks, one module per purpose, run in the order of GROUPS
below (the order of the report); helpers.py has what they share. The groups after
sensitivity rely on its made-up CLOUDFLARE_API_TOKEN, which stays in the environment.

Standard library, sh and jq; no provider credentials. The last parts download the cloudflare
provider for the mock (terraform init). TERRAFORM sets the binary (default: terraform).
"""
from plan_checks import apply_order, computed, computed_v4, helpers, messages, migrations, sensitivity

GROUPS = [
    computed,      # values known after apply: plan and apply of the input checks
    apply_order,   # checks over all records through compile: failure and the state after it
    messages,      # the full text of the messages
    sensitivity,   # the records output in the plan JSON
    computed_v4,   # the v4 wrapper with values known after apply
    migrations,    # v4 to v5 and the 2.x keys (moved blocks)
]

for group in GROUPS:
    group.main()

if helpers.failed:
    raise SystemExit(f'Failed: {", ".join(helpers.failed)}')
