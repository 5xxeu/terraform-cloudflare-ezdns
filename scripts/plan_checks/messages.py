"""The full text of the messages of the checks: from modules/dns/checks alone and through the wrappers"""

from pathlib import Path
import tempfile

from .helpers import CHECKS, MESSAGES, ROOT, failed_with, init, report, run


# The messages that take the context of the call, from modules/dns/checks alone
CONTEXT = [
    ('low_ttls with minimum_ttl 60', {'minimum_ttl': '60', 'low_ttls': '["default_ttl (30)"]'},
     MESSAGES['low_ttls'].format(minimum_ttl=60) + 'default_ttl (30)'),
    ('low_ttls with minimum_ttl 30', {'minimum_ttl': '30', 'low_ttls': '["a", "b"]'},
     MESSAGES['low_ttls'].format(minimum_ttl=30) + 'a\nb'),
    ('not_owned without exclude', {'owned_include': '["a.example.com", "b.example.com"]', 'not_owned': '["x"]'},
     MESSAGES['not_owned'].format(include='a.example.com, b.example.com', exclude='none') + 'x'),
    ('not_owned with exclude', {'owned_exclude': '["k8s.a.example.com", "c.a.example.com"]', 'not_owned': '["x", "y"]'},
     MESSAGES['not_owned'].format(include='a.example.com', exclude='k8s.a.example.com, c.a.example.com') + 'x\ny'),
]


def main():
    with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
        directory = Path(tmp)
        for name, arguments, message in CONTEXT:
            inputs = {
                'flat_records': '{}', 'minimum_ttl': '60', 'owned_include': '["a.example.com"]', 'owned_exclude': '[]',
                **{check: '[]' for check, _, _ in CHECKS}, **arguments,
            }
            # The inputs come from variables of the root module, as in the wrappers from the
            # outputs of the records module: on Terraform 1.9.0 a failing validation of a
            # constant argument whose message refers to another input shows "Failed to
            # evaluate condition error message" instead of the message
            (directory / 'main.tf').write_text(''.join(f'variable "{k}" {{\n  default = {v}\n}}\n\n' for k, v in inputs.items())
                                               + 'module "checks" {\n  source = "../modules/dns/checks"\n\n%s}\n' % ''.join(f'  {k} = var.{k}\n' for k in inputs))
            init(directory)
            result = run(['plan', '-json'], directory)
            report(f'checks: message of {name}', failed_with(result, message), result[1])

    # Through the v4 and v5 wrappers and the root module with a mock provider. A run that fails
    # skips the runs after it, so each case is a test file of its own; the v4 wrapper has a
    # directory of its own (its provider version differs, and so does the lock file)
    for label, source in [('v5', '../modules/dns/v5'), ('v4', '../modules/dns/v4'), ('root', './..')]:
        with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
            directory = Path(tmp)
            (directory / 'versions.tf').write_text('terraform {\n  required_providers {\n    cloudflare = {\n      source = "cloudflare/cloudflare"\n    }\n  }\n}\n')
            for check, arguments, message in CHECKS:
                for old in directory.glob('*.tftest.hcl'):
                    old.unlink()
                (directory / f'{check}.tftest.hcl').write_text('''mock_provider "cloudflare" {}

run "%s" {
  command = plan

  module {
    source = "%s"
  }

  variables {
    zone_id   = "z"
    zone_name = "example.com"
    %s
  }
}
''' % (check, source, '\n    '.join(arguments)))
                # init installs the module of the run (the provider stays in .terraform)
                init(directory)
                result = run(['test', '-json'], directory)
                report(f'{label}: {check} fails the plan', failed_with(result, message), result[1])
