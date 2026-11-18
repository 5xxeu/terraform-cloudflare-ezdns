"""The v4 wrapper with values known only after apply: the keys of the records stay known at plan"""

import json
from pathlib import Path
import tempfile

from .helpers import ROOT, init, report, run


# The v4 wrapper with a content known only after apply (plan only: the provider gets a
# made-up token and creates nothing): the keys of the records stay known at plan, so
# for_each works, with an explicit key and with the normalized key of a known value; also
# with a zone ID known only after apply and no zone_name, and with a zone_name known only
# after apply (the cases of modules/dns/idna/tests/computed_zone). A zone_name that is
# null at plan and known later would make the count of the lookup unknown, as in the v5
# wrapper


def main():
    with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
        directory = Path(tmp)
        (directory / 'main.tf').write_text('''resource "terraform_data" "value" {
  input = "192.0.2.9"
}

module "dns" {
  source    = "../modules/dns/v4"
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    "WEB" = {
      A = [{ key = "web", content = terraform_data.value.output }, { content = "192.0.2.2" }]
    }
    "ALIAS" = { CNAME = [{ content = terraform_data.value.output }] }
  }
}

resource "terraform_data" "zone" {
  input = "z${timestamp()}"
}

# A zone ID known only after apply and no zone_name: no lookup of the zone may stop the plan
module "dns_zone_id" {
  source  = "../modules/dns/v4"
  zone_id = terraform_data.zone.output
  records = { "app" = { A = [{ key = "a", content = terraform_data.value.output }] } }
}

# A zone_name known only after apply (not null), with a content known after apply
module "dns_zone_name" {
  source    = "../modules/dns/v4"
  zone_id   = "z"
  zone_name = "example.com${substr(timestamp(), 0, 0)}"
  records = {
    "app"  = { A = [{ key = "a", content = terraform_data.value.output }] }
    "Shop" = { AAAA = [{ content = "2001:DB8::1" }] }
  }
}
''')
        init(directory)
        code, output = run(['plan', '-out=tfplan'], directory)
        shown = run(['show', '-json', 'tfplan'], directory)
        try:
            keys = sorted(c['module_address'].split('.')[-1] + ' ' + c['index'] for c in json.loads(shown[1])['resource_changes'] if c['type'] == 'cloudflare_record')
        except (ValueError, KeyError):
            keys = []
        report('v4: keys known at plan with a content, a zone ID and a zone_name known after apply', code == 0 and keys == [
            'dns alias CNAME', 'dns web A 192.0.2.2', 'dns web A web',
            'dns_zone_id app A a', 'dns_zone_name app A a', 'dns_zone_name shop AAAA 2001:db8::1'], output + str(keys))
