#!/usr/bin/env python3
"""Check the input checks of records with values known only after apply.

A check of an input fails at plan when the values it looks at are known, and is put off
until apply when they are not; the keys of records with a key stay known at plan.
terraform test cannot expect a failure in a called module, so these cases are planned
(and some applied) through compile, which needs no provider: a terraform_data with
for_each over its records stands for the resources of the wrappers, whose keys must be
known at plan. Standard library only; no provider credentials or provider downloads
required. TERRAFORM sets the binary (default: terraform).
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
terraform = os.environ.get('TERRAFORM', 'terraform')

# A TTL and a text value from another resource are unknown at plan
TTL = 'tonumber(terraform_data.ttl.output)'
VALUE = 'terraform_data.value.output'
# (name, arguments, expected at plan, expected at apply): None for success, or a text
# of the error; apply is run only when it is not False
CASES = [
    ('records with an unknown attribute',
     'records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s, proxid = true }] } }' % TTL,
     'records["@"]["A"][0]: unknown attribute "proxid"', False),
    ('record_groups with an unknown attribute',
     'record_groups = { web = { records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s, proxid = true }] } } } }' % TTL,
     'record_groups["web"].records["@"]["A"][0]: unknown attribute "proxid"', False),
    ('valid records and empty containers',
     'records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s }] }, app = [] }\n'
     '  record_groups = { web = { records = { www = { A = [{ content = "192.0.2.2", ttl = %s }], TXT = {} } } } }' % (TTL, TTL),
     None, False),
    ('records with an attribute that does not apply to the type',
     'records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s, priority = 10 }] } }' % TTL,
     'records["@"]["A"][0].priority', False),
    ('record_groups with an attribute that does not apply to the type',
     'record_groups = { web = { records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s, priority = 10 }] } } } }' % TTL,
     'record_groups["web"].records["@"]["A"][0].priority', False),
    # The keys stay known: records and grouped records with a key and a computed content
    ('content known after apply, with a key',
     'records = { "@" = { A = [{ content = %s, key = "c1" }] } }\n'
     '  record_groups = { web = { records = { www = { TXT = [{ content = %s, key = "c2" }] } } } }' % (VALUE, VALUE),
     None, None),
    # The check of an attribute with a value known only after apply is put off until apply
    ('records with a computed attribute that does not apply to the type',
     'records = { "@" = { A = [{ content = "192.0.2.1", priority = %s }] } }' % TTL,
     None, 'records["@"]["A"][0].priority'),
    ('record_groups with a computed attribute that does not apply to the type',
     'record_groups = { web = { records = { "@" = { A = [{ content = "192.0.2.1", priority = %s }] } } } }' % TTL,
     None, 'record_groups["web"].records["@"]["A"][0].priority'),
    # Expected: without a key, a record is keyed by its value, so a value known only
    # after apply makes its key unknown and the resources cannot be planned
    ('content known after apply, without a key',
     'records = { "@" = { A = [{ content = %s }] } }' % VALUE,
     'Invalid for_each argument', False),
]

def run(command, directory):
    result = subprocess.run([terraform, *command, '-input=false', '-no-color'], cwd=directory, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def matches(expected, code, output):
    return code == 0 if expected is None else code != 0 and expected in output


failed = []
with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
    directory = Path(tmp)
    for name, arguments, expected_plan, expected_apply in CASES:
        (directory / 'main.tf').write_text('''
resource "terraform_data" "ttl" {
  input = 300
}

resource "terraform_data" "value" {
  input = "192.0.2.50"
}

module "dns" {
  source    = "../modules/dns/compile"
  zone_name = "example.com"
  %s
}

resource "terraform_data" "records" {
  for_each = module.dns.records
}
''' % arguments)
        (directory / 'terraform.tfstate').unlink(missing_ok=True)
        subprocess.run([terraform, 'init', '-backend=false', '-input=false', '-no-color'], cwd=directory, check=True, stdout=subprocess.DEVNULL)
        code, output = run(['plan'], directory)
        ok = matches(expected_plan, code, output)
        if ok and expected_apply is not False:
            code, output = run(['apply', '-auto-approve'], directory)
            ok = matches(expected_apply, code, output)
        print(f'{"ok  " if ok else "FAIL"} {name}')
        if not ok:
            print(output)
            failed.append(name)

if failed:
    raise SystemExit(f'Failed: {", ".join(failed)}')
