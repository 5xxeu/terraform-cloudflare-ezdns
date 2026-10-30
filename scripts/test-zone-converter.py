#!/usr/bin/env python3
"""Check equivalent zone records through compile with ordinary and stable keys.

Standard library only; no provider credentials or provider downloads required.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('zone_converter', ROOT / 'tools/zone-to-ezdns.py')
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)
fixture = json.loads((ROOT / 'tools/tests/fixtures/equivalent-zone.json').read_text())
terraform = os.environ.get('TERRAFORM', 'terraform')
with tempfile.TemporaryDirectory(prefix='.converter-test-', dir=ROOT) as tmp:
    directory = Path(tmp)
    (directory / 'main.tf').write_text('''
module "dns" {
  source = %s
  zone_name = "example.com"
  records = yamldecode(file("${path.module}/records.yaml")).records
}
output "records" { value = module.dns.records }
''' % json.dumps('../modules/dns/compile'))
    (directory / 'main.tftest.hcl').write_text('''
run "equivalent_records" {
  command = plan
  assert {
    condition = length(output.records) == %d
    error_message = "Equivalent copies must collapse and distinct priorities or flags must remain"
  }
}
''' % fixture['expected_count'])
    subprocess.run([terraform, 'init', '-backend=false', '-input=false', '-no-color'], cwd=directory, check=True, stdout=subprocess.DEVNULL)
    for stable in (False, True):
        records, notes = z.convert(fixture['result'], 'example.com', 3600, stable)
        assert len(notes) == fixture['expected_copies'], notes
        assert all('written once' in note for note in notes), notes
        (directory / 'records.yaml').write_text(z.to_yaml(records, 'example.com', fixture['expected_count']))
        result = subprocess.run([terraform, 'test', '-no-color'], cwd=directory, capture_output=True, text=True)
        print(f'stable_keys={stable}: {result.stdout.strip()}')
        if result.returncode or 'Warning:' in result.stdout + result.stderr:
            raise SystemExit(result.stderr or result.stdout)
