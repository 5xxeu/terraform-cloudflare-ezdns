#!/usr/bin/env python3
"""Check that the input checks fail at plan when a record value is known only after apply.

terraform test cannot expect a failure in a called module, so these cases are planned
through compile. Standard library only; no provider credentials or provider downloads
required. TERRAFORM sets the binary (default: terraform).
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
terraform = os.environ.get('TERRAFORM', 'terraform')

# A TTL from another resource is unknown at plan
TTL = 'tonumber(terraform_data.ttl.output)'
CASES = [
    ('records with an unknown attribute',
     'records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s, proxid = true }] } }' % TTL,
     'records["@"]["A"][0]: unknown attribute "proxid"'),
    ('record_groups with an unknown attribute',
     'record_groups = { web = { records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s, proxid = true }] } } } }' % TTL,
     'record_groups["web"].records["@"]["A"][0]: unknown attribute "proxid"'),
    ('valid records and empty containers',
     'records = { "@" = { A = [{ content = "192.0.2.1", ttl = %s }] }, app = [] }\n'
     '  record_groups = { web = { records = { www = { A = [{ content = "192.0.2.2", ttl = %s }], TXT = {} } } } }' % (TTL, TTL),
     None),
]

failed = []
with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
    directory = Path(tmp)
    for name, arguments, expected in CASES:
        (directory / 'main.tf').write_text('''
resource "terraform_data" "ttl" {
  input = 300
}

module "dns" {
  source    = "../modules/dns/compile"
  zone_name = "example.com"
  %s
}
''' % arguments)
        subprocess.run([terraform, 'init', '-backend=false', '-input=false', '-no-color'], cwd=directory, check=True, stdout=subprocess.DEVNULL)
        result = subprocess.run([terraform, 'plan', '-input=false', '-no-color'], cwd=directory, capture_output=True, text=True)
        output = result.stdout + result.stderr
        if expected is None:
            ok = result.returncode == 0
        else:
            ok = result.returncode != 0 and expected in output
        print(f'{"ok  " if ok else "FAIL"} {name}')
        if not ok:
            print(output)
            failed.append(name)

if failed:
    raise SystemExit(f'Failed: {", ".join(failed)}')
