"""The checks over all records through compile: failure at plan or at apply, and the state of the records after it"""

import json
from pathlib import Path
import tempfile

from .helpers import CHECKS, ROOT, SAME_A, TTL, VALUE, failed_with, init, report, run


# The checks over all records through compile. terraform_data.records stands for the
# resources of the wrappers; ttl, value, flag and zone give values known only after
# apply (a new input of value makes its output unknown again)
COMPILE = '''
resource "terraform_data" "ttl" {
  input = 300
}

resource "terraform_data" "value" {
  input = "%(value)s"
}

resource "terraform_data" "flag" {
  input = true
}

resource "terraform_data" "zone" {
  input = "example.com"
}

module "dns" {
  source    = "../modules/dns/compile"
  zone_name = %(zone)s
  %(arguments)s
}

resource "terraform_data" "records" {
  for_each = nonsensitive(module.dns.records)
  input    = each.value
}
'''


def records_in_state(directory):
    """The records resources in the state: key => (content, ttl)"""
    code, output = run(['show', '-json'], directory)
    if code != 0:
        raise SystemExit(output)
    resources = (json.loads(output).get('values') or {}).get('root_module', {}).get('resources', [])
    return {
        r['index']: (r['values']['input']['content'], r['values']['input']['ttl'])
        for r in resources if r['address'].startswith('terraform_data.records[')
    }


def fresh(directory):
    for name in ['terraform.tfstate', 'terraform.tfstate.backup', 'tfplan']:
        (directory / name).unlink(missing_ok=True)


def step(directory, arguments, value='192.0.2.50', zone='"example.com"'):
    """Plans the configuration into a file and applies that file. Returns the result of
    plan, the result of apply (None when the plan failed), the records in the state and
    the output of both for a report"""
    (directory / 'main.tf').write_text(COMPILE % {'value': value, 'zone': zone, 'arguments': '\n  '.join(arguments)})
    init(directory)
    plan = run(['plan', '-json', '-out=tfplan'], directory)
    applied = run(['apply', '-json', 'tfplan'], directory) if plan[0] == 0 else None
    records = records_in_state(directory)
    return plan, applied, records, plan[1] + (applied[1] if applied else '') + '\nState: ' + json.dumps(records)


def passed(result):
    return result is not None and result[0] == 0


def main():
    with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
        directory = Path(tmp)

        # Every check fails at plan with its message, and nothing is applied
        for check, arguments, message in CHECKS:
            fresh(directory)
            plan, applied, records, output = step(directory, arguments)
            report(f'compile: {check} fails at plan', failed_with(plan, message) and applied is None and not records, output)

        # Values known only after apply in a valid configuration: the plan passes and the
        # records are applied
        fresh(directory)
        plan, applied, records, output = step(directory, [
            'records = {',
            '  "app" = { A = [{ key = "a", content = "192.0.2.1", ttl = %s, proxied = terraform_data.flag.output }] }' % TTL,
            '  "www" = { CNAME = [{ key = "w", content = %s }] }' % VALUE,
            '}',
        ], value='target.example.net')
        report('compile: TTL, proxied and CNAME target known after apply pass', passed(plan) and passed(applied) and len(records) == 2, output)
        fresh(directory)
        plan, applied, records, output = step(directory, ['records = { "app" = { A = [{ content = "192.0.2.1" }] }, "www" = { CNAME = [{ content = "app" }] } }'], zone='terraform_data.zone.output')
        report('compile: zone known after apply passes', passed(plan) and passed(applied) and len(records) == 2, output)

        # Normalized keys need neither the zone nor the values of other records: with a zone
        # and an address under a key known only after apply, the other forms get their keys
        # at plan (one AAAA map over all addresses would make them unknown)
        fresh(directory)
        plan, applied, records, output = step(directory, [
            'records = {',
            '  "WEB" = { AAAA = [{ key = "web", content = %s }, { content = "2001:DB8:0::2" }] }' % VALUE,
            '  "@"   = { MX = [{ content = "Mail.Example.com.", priority = 10 }] }',
            '}',
        ], value='2001:db8::1', zone='terraform_data.zone.output')
        report('compile: normalized keys known at plan with a zone and an address known after apply',
               passed(plan) and passed(applied) and sorted(records) == ['@ MX mail.example.com', 'web AAAA 2001:db8::2', 'web AAAA web'], output)

        # A value known only after apply that makes two records the same: the check of
        # same_values waits for apply and fails there, before any record is created
        fresh(directory)
        plan, applied, records, output = step(directory, ['records = { "app" = { A = [{ key = "a", content = "192.0.2.1" }, { key = "b", content = %s }] } }' % VALUE], value='192.0.2.1')
        report('compile: value known after apply that makes a duplicate fails at apply, nothing created',
               passed(plan) and applied is not None and failed_with(applied, SAME_A) and not records, output)

        # The same for an update: a record in the state whose change is planned together with
        # the failing check keeps its values
        fresh(directory)
        applied_before = {'app A a': ('192.0.2.1', 300), 'app A b': ('192.0.2.2', 3600)}
        plan, applied, records, output = step(directory, ['records = { "app" = { A = [{ key = "a", content = "192.0.2.1", ttl = 300 }, { key = "b", content = %s }] } }' % VALUE], value='192.0.2.2')
        ok = passed(plan) and passed(applied) and records == applied_before
        plan, applied, records, output = step(directory, ['records = { "app" = { A = [{ key = "a", content = "192.0.2.1", ttl = 600 }, { key = "b", content = %s }] } }' % VALUE], value='192.0.2.1')
        report('compile: value known after apply that makes a duplicate fails at apply, nothing changed',
               ok and passed(plan) and applied is not None and failed_with(applied, SAME_A) and records == applied_before, output)

        # A known duplicate key fails at plan also next to a record with a value known only
        # after apply
        fresh(directory)
        plan, applied, records, output = step(directory, ['records = { "app" = { TXT = [{ key = "foo", content = "a" }, { key = "foo", content = "b" }, { key = "c", content = %s }] } }' % VALUE])
        report('compile: known duplicate next to a value known after apply fails at plan',
               failed_with(plan, CHECKS[0][2]) and applied is None and not records, output)

        # Two records with the same value next to a third one whose value is known only after
        # apply: the list of same_values is unknown at plan (as in 2.x), so the check waits
        # for apply and fails there, before any record is created
        fresh(directory)
        plan, applied, records, output = step(directory, ['records = { "app" = { A = [{ key = "a", content = "192.0.2.1" }, { key = "b", content = "192.0.2.1" }, { key = "c", content = %s }] } }' % VALUE], value='192.0.2.3')
        report('compile: same values next to a value known after apply fail at apply, nothing created',
               passed(plan) and applied is not None and failed_with(applied, SAME_A) and not records, output)

        # An attribute that does not apply to the type, known only after apply: the check of
        # the input waits for apply and fails there, before any record is created or changed
        # (the saved plan is applied, the state is read)
        UNUSED = ('These attributes do not apply to the type of their record (SRV keeps its priority in data; content is for records without data; tag and flags are for CAA; name is for ALIASES, which have the name of the CNAME they create in name, not in content). Remove them:\n')
        for label, wrap, path in [
            ('records', 'records = { "app" = { A = [%s] } }', 'records["app"]["A"][0].priority'),
            ('record_groups', 'record_groups = { web = { records = { "app" = { A = [%s] } } } }', 'record_groups["web"].records["app"]["A"][0].priority'),
        ]:
            fresh(directory)
            plan, applied, records, output = step(directory, [wrap % '{ key = "a", content = "192.0.2.1", priority = tonumber(terraform_data.value.output) }'], value='10')
            report(f'compile: {label}: computed attribute that does not apply fails at apply, nothing created',
                   passed(plan) and applied is not None and failed_with(applied, UNUSED + path) and not records, output)
            fresh(directory)
            before = {'app A a': ('192.0.2.1', 300)}
            plan, applied, records, output = step(directory, [wrap % '{ key = "a", content = "192.0.2.1", ttl = 300 }'], value='10')
            ok = passed(plan) and passed(applied) and records == before
            plan, applied, records, output = step(directory, [wrap % '{ key = "a", content = "192.0.2.2", ttl = 600, priority = tonumber(terraform_data.value.output) }'], value='11')
            report(f'compile: {label}: computed attribute that does not apply fails at apply, nothing changed',
                   ok and passed(plan) and applied is not None and failed_with(applied, UNUSED + path) and records == before, output)
