"""Moving the state: from the v4 wrapper to v5, and from the 2.x keys to the normalized keys"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from .helpers import ROOT, init, report, run, terraform


# Switching from the v4 wrapper to the v5 wrapper (docs/upgrading.md): the state of a record
# of the v4 wrapper after the apply of 3.0 (the keys of the moved blocks), the file of
# moved blocks of that step left in place (the docs tell to delete it), and the source
# switched to v5. migrate-from-v4.tf moves the address from cloudflare_record to
# cloudflare_dns_record, and the real provider v5 converts the instance (MoveResourceState,
# which a mock provider does not do; the made-up token is never used, nothing is read with
# -refresh=false): the plan has one move and no record to create or delete. Without
# migrate-from-v4.tf there is no move: the plan fails (or would create the record)
def v4_to_v5(directory, with_migration_file):
    config = '''terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

module "dns" {
  source    = "../modules/dns/%s"
  zone_id   = "z"
  zone_name = "example.com"
  records   = { "WWW" = { A = [{ content = "192.0.2.1" }] } }
}
'''
    (directory / 'main.tf').write_text(config % 'v4')
    init(directory)
    code, output = run(['plan', '-out=v4.tfplan'], directory)
    planned = json.loads(run(['show', '-json', 'v4.tfplan'], directory)[1])
    change = [c for c in planned['resource_changes'] if c['type'] == 'cloudflare_record'][0]
    schema = json.loads(subprocess.run([terraform, 'providers', 'schema', '-json'], cwd=directory,
                                       capture_output=True, text=True, check=True).stdout)
    version = schema['provider_schemas']['registry.terraform.io/cloudflare/cloudflare']['resource_schemas']['cloudflare_record']['version']
    (directory / 'terraform.tfstate').write_text(json.dumps({
        'version': 4, 'terraform_version': '1.9.0', 'serial': 1, 'lineage': 'plan-checks', 'outputs': {},
        'resources': [{'module': change['module_address'], 'mode': 'managed', 'type': 'cloudflare_record',
                       'name': 'record', 'provider': 'provider["registry.terraform.io/cloudflare/cloudflare"]',
                       'instances': [{'index_key': change['index'], 'schema_version': version, 'sensitive_attributes': [],
                                      'attributes': dict(change['change']['after'], id='0' * 32)}]}]}))
    (directory / 'dns_migration.tf').write_text('''moved {
  from = module.dns.cloudflare_record.record["WWW A 192.0.2.1"]
  to   = module.dns.cloudflare_record.record["www A 192.0.2.1"]
}
''')
    (directory / 'main.tf').write_text(config % ('v5' if with_migration_file else 'v5-without-migration'))
    return directory


# Records in other forms (each moves) next to one in the canonical form (stays). The
# explicit key holds template sequences, which the command escapes in the addresses
FORMS = {
    'WWW': {'A': [{'content': '192.0.2.1'}], 'TXT': [{'content': 'v=1', 'key': '${1+1}%{if-true}x'}]},
    'app': {'AAAA': [{'content': '2001:DB8:0:0:0:0:0:1'}]},
    '@': {'MX': [{'content': 'Mail.Example.com.', 'priority': 10}]},
    '_SIP._tcp': {'SRV': [{'data': {'priority': '10.0', 'weight': 5, 'port': 5060, 'target': 'sip.example.com'}}]},
    'static': {'A': [{'content': '192.0.2.2'}]},
}


def main():
    for with_file in (True, False):
        with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
            directory = Path(tmp)
            output = ''
            copy = None
            try:
                if with_file:
                    v4_to_v5(directory, True)
                else:
                    # a copy of the v5 wrapper without migrate-from-v4.tf, next to the core modules
                    copy = ROOT / 'modules/dns' / f'v5-without-migration-{directory.name.lstrip(".")}'
                    shutil.copytree(ROOT / 'modules/dns/v5', copy, ignore=shutil.ignore_patterns('.terraform*', 'tests', 'migrate-from-v4.tf'))
                    v4_to_v5(directory, False)
                    (directory / 'main.tf').write_text((directory / 'main.tf').read_text().replace('v5-without-migration', copy.name))
                # another provider version than the v4 step: the lock file is replaced
                (directory / '.terraform.lock.hcl').unlink(missing_ok=True)
                subprocess.run([terraform, 'init', '-upgrade', '-backend=false', '-input=false', '-no-color'], cwd=directory, capture_output=True, text=True, check=True)
                code, output = run(['plan', '-refresh=false', '-out=v5.tfplan'], directory)
                if code != 0 and not with_file:
                    # without the file Terraform cannot read the instance of a resource that the
                    # configuration no longer has at that type: the plan fails
                    ok = 'no schema available for module.dns.cloudflare_record.record' in output
                    changes = []
                else:
                    changes = [c for c in json.loads(run(['show', '-json', 'v5.tfplan'], directory)[1])['resource_changes']
                               if c['type'] in ('cloudflare_record', 'cloudflare_dns_record')]
                actions = sorted(c['change']['actions'][0] if len(c['change']['actions']) == 1 else '+'.join(c['change']['actions']) for c in changes)
                moved = [c for c in changes if c.get('previous_address')]
                if with_file:
                    ok = (code == 0 and len(changes) == 1 and len(moved) == 1 and actions == ['no-op']
                          and moved[0]['type'] == 'cloudflare_dns_record' and moved[0]['previous_address'].endswith('cloudflare_record.record["www A 192.0.2.1"]'))
                elif code == 0:
                    ok = not moved and 'create' in actions
            except (ValueError, KeyError, IndexError, OSError, subprocess.CalledProcessError) as error:
                ok = False
                output += f'\n{error!r}'
            finally:
                if copy is not None:
                    shutil.rmtree(copy, ignore_errors=True)
            report('v4 to v5: ' + ('migrate-from-v4.tf moves the record of the v4 wrapper without create or delete, with the left-over moved file in place'
                                   if with_file else 'without migrate-from-v4.tf the same state is not moved (the plan fails or creates the record)'), ok, output[-3000:])

    # The moved blocks of docs/upgrading.md ("To 3.0, Normalized Record Keys") on the three
    # addresses of the records: a state with the 2.x keys (the keys of state_migration, on
    # the values that the plan gives the records) is moved by the blocks that the command of
    # the docs writes, without records to create or delete. Made-up token, no refresh:
    # nothing is read from Cloudflare. Needs jq and sh
    upgrading = (ROOT / 'docs/upgrading.md').read_text()
    section = upgrading[upgrading.index('### Normalized Record Keys'):]
    command = section[section.index('```sh') + len('```sh'):]
    command = '\n'.join(line[3:] for line in command[:command.index('```')].splitlines()
                        if line.strip() and not line.strip().startswith(('#', 'ADDRESS=')))
    for label, source, address in [
        ('root', './..', 'module.dns.module.v5.cloudflare_dns_record.record'),
        ('v5', '../modules/dns/v5', 'module.dns.cloudflare_dns_record.record'),
        ('idna', '../modules/dns/idna', 'module.dns.module.v5.cloudflare_dns_record.record'),
        ('v4', '../modules/dns/v4', 'module.dns.cloudflare_record.record'),
        # a call named v4 (docs/upgrading.md: the module name is not taken from the path)
        ('v4 named v4', '../modules/dns/v4', 'module.v4.cloudflare_record.record'),
    ]:
        resource_type = address.rsplit('.', 2)[1]
        module_name = address.split('.')[1]
        with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
            directory = Path(tmp)
            (directory / 'records.json').write_text(json.dumps(FORMS))
            (directory / 'main.tf').write_text('''terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

module "%s" {
  source    = "%s"
  zone_id   = "z"
  zone_name = "example.com"
  records   = jsondecode(file("records.json"))
}
''' % (module_name, source))
            init(directory)
            ok, output = False, ''
            try:
                code, output = run(['plan', '-out=new.tfplan'], directory)
                planned = json.loads(run(['show', '-json', 'new.tfplan'], directory)[1])
                schema = json.loads(subprocess.run([terraform, 'providers', 'schema', '-json'], cwd=directory,
                                                   capture_output=True, text=True, check=True).stdout)
                version = schema['provider_schemas']['registry.terraform.io/cloudflare/cloudflare']['resource_schemas'][resource_type]['version']
                migration = json.loads(json.loads(subprocess.run(
                    [terraform, 'console'], input='jsonencode(nonsensitive(module.%s.state_migration))' % module_name + '', cwd=directory,
                    capture_output=True, text=True, check=True).stdout.strip().splitlines()[-1]))
                old_keys = {new: old for old, new in migration.items()}
                changes = [c for c in planned['resource_changes'] if c['type'] == resource_type]
                resource = changes[0]
                instances = [{'index_key': old_keys.get(c['index'], c['index']), 'schema_version': version, 'sensitive_attributes': [],
                              'attributes': dict(c['change']['after'], id=f'{n:032x}')} for n, c in enumerate(changes)]
                (directory / 'terraform.tfstate').write_text(json.dumps({
                    'version': 4, 'terraform_version': '1.9.0', 'serial': 1, 'lineage': 'plan-checks', 'outputs': {},
                    'resources': [{'module': resource['module_address'], 'mode': 'managed', 'type': resource_type,
                                   'name': 'record', 'provider': 'provider["registry.terraform.io/cloudflare/cloudflare"]',
                                   'instances': instances}]}))
                # Terraform writes the addresses with the template sequences escaped
                before = sorted(f'{address}[{json.dumps(i["index_key"]).replace("${", "$${").replace("%{", "%%{")}]' for i in instances)
                generated = subprocess.run(['sh', '-c', f'ADDRESS={address}\n{command}'], cwd=directory, capture_output=True, text=True,
                                           env=dict(os.environ, PATH=f'{Path(terraform).resolve().parent}:{os.environ["PATH"]}' if '/' in terraform else os.environ['PATH']))
                output = generated.stdout + generated.stderr
                blocks = (directory / 'dns_migration.tf').read_text().count('moved {')
                code, output = run(['plan', '-refresh=false', '-out=moved.tfplan'], directory)
                moved = [c for c in json.loads(run(['show', '-json', 'moved.tfplan'], directory)[1])['resource_changes']
                         if c['type'] == resource_type]
                moves = [c for c in moved if c.get('previous_address', c['address']) != c['address']]
                ok = (code == 0 and blocks == len(migration) == len(moves) == 5
                      and all(c['change']['actions'] in (['no-op'], ['update']) for c in moved)
                      and sorted(c.get('previous_address', c['address']) for c in moved) == before)
            except (ValueError, KeyError, IndexError, OSError, subprocess.CalledProcessError) as error:
                output += f'\n{error!r}'
            report(f'{label}: moved blocks of docs/upgrading.md move the 2.x keys of {address}', ok, output[-3000:])
