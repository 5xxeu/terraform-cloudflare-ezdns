"""Sensitivity of the records output in the plan JSON"""

import json
import os
from pathlib import Path
import tempfile

from .helpers import ROOT, init, report, run


# The records output of root, v5, v4, idna and compile is sensitive in the plan JSON of the
# module as a root module (a caller must mark its own output, and Terraform 1.9.0 does not
# carry the mark through a module call), record_metadata is not. The provider gets a
# made-up token: the plan reads nothing from Cloudflare


def main():
    os.environ['CLOUDFLARE_API_TOKEN'] = '0123456789abcdef0123456789abcdef01234567'
    with tempfile.TemporaryDirectory() as tmp:
        for label, module in [('root', ROOT), ('v5', ROOT / 'modules/dns/v5'), ('v4', ROOT / 'modules/dns/v4'), ('idna', ROOT / 'modules/dns/idna'), ('compile', ROOT / 'modules/dns/compile')]:
            wrapper = label != 'compile'
            variables = {'zone_name': 'example.com', 'records': {'app': {'A': [{'content': '192.0.2.1', 'proxied': True}]}}}
            if wrapper:
                variables['zone_id'] = 'z'
            varfile = Path(tmp) / f'{label}.tfvars.json'
            varfile.write_text(json.dumps(variables))
            planfile = Path(tmp) / f'{label}.tfplan'
            init(module)
            result = run(['plan', f'-var-file={varfile}', f'-out={planfile}'], module)
            shown = run(['show', '-json', str(planfile)], module)
            try:
                changes = json.loads(shown[1])['output_changes']
                marked = changes['records']['after_sensitive'] is True and (not wrapper or changes['record_metadata']['after_sensitive'] is False)
            except (ValueError, KeyError):
                marked = False
            report(f'{label}: records is sensitive in the plan JSON, record_metadata is not', result[0] == 0 and marked, result[1] + shown[1][:2000])
