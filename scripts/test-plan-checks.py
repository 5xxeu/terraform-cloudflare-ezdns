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

Standard library, sh and jq; no provider credentials. The last parts download the cloudflare
provider for the mock (terraform init). TERRAFORM sets the binary (default: terraform).
"""
import json
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
    ('ALIASES with content (2.x syntax, the name is in name)',
     'records = { "@" = { ALIASES = [{ content = "www" }] } }',
     'records["@"]["ALIASES"][0].content', False),
    ('record_groups with ALIASES that have content',
     'record_groups = { web = { records = { "@" = { "cdn.ALIASES" = [{ content = "static" }] } } } }',
     'record_groups["web"].records["@"]["cdn.ALIASES"][0].content', False),
    ('ALIASES with name',
     'records = { "@" = { ALIASES = [{ name = "www", ttl = %s }] } }' % TTL,
     None, False),
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

# The messages of modules/dns/checks (variables.tf), as a caller sees them
MESSAGES = {
    'duplicates': 'Duplicate records (remove the duplicates or set a unique key for each of them; MX records that differ only in priority and CAA records that differ only in flags have the same key and need a key too):\n',
    'same_values': 'Records with the same name, type and value under different keys, which Cloudflare rejects as identical records (remove all but one of them):\n',
    'low_ttls': 'TTLs below {minimum_ttl} seconds are only available on the Cloudflare Enterprise plan. If this zone is on Enterprise, set minimum_ttl = 30 in the module call; otherwise use a TTL of at least 60 seconds, or 1 for automatic:\n',
    'missing_keys': 'require_keys lists the types of these records, so each of them needs a key (e.g. key = "web"): with a key, a new value is an update in place, without one the record is deleted and created again:\n',
    'misplaced_wildcards': 'A wildcard must be the whole leftmost label of a name ("*", "*.app"); these names put it elsewhere:\n',
    'long_names': 'A fully qualified name can have at most 253 characters; these names and alias targets (prefix, name and zone together) are longer:\n',
    'self_cnames': 'A CNAME (or alias) cannot point to its own name:\n',
    'not_owned': 'These records are outside owned_names (included: {include}; excluded: {exclude}), the part of the zone that this module call manages:\n',
    'cname_conflicts': 'A CNAME record cannot share its name with other records (except at the zone apex, where only A and AAAA conflict with it), and a name has at most one CNAME. Names that already have a CNAME next to other records in the zone can be listed in allowed_cname_conflicts:\n',
}
LONG = '.'.join(['a' * 63] * 4)
SAME_A = MESSAGES['same_values'] + 'A app.example.com from records["app"]["A"][0] and records["app"]["A"][1]'
# One failing configuration per check (arguments of the module call, one per line), and
# the full message it gives
CHECKS = [
    ('duplicates',
     ['records = { "app" = { TXT = [{ key = "foo", content = "a" }, { key = "foo", content = "b" }] } }'],
     MESSAGES['duplicates'] + '"app TXT foo" from records["app"]["TXT"][0] and records["app"]["TXT"][1]'),
    ('same_values',
     ['records = { "app" = { TXT = [{ key = "foo", content = "a" }, { key = "bar", content = "a" }] } }'],
     MESSAGES['same_values'] + 'TXT app.example.com from records["app"]["TXT"][0] and records["app"]["TXT"][1]'),
    ('low_ttls',
     ['minimum_ttl = "60"', 'records = { "app" = { A = [{ content = "192.0.2.1", ttl = 30 }] } }'],
     MESSAGES['low_ttls'].format(minimum_ttl=60) + '"app A 192.0.2.1" (ttl 30) from records["app"]["A"][0]'),
    ('missing_keys',
     ['require_keys = ["A"]', 'records = { "app" = { A = [{ content = "192.0.2.1" }] } }'],
     MESSAGES['missing_keys'] + 'A app.example.com from records["app"]["A"][0]'),
    ('misplaced_wildcards',
     ['records = { "*" = { "_acme-challenge.TXT" = [{ content = "token" }] } }'],
     MESSAGES['misplaced_wildcards'] + '"_acme-challenge.*" from records["*"]["_acme-challenge.TXT"][0]'),
    ('long_names',
     ['records = { "%s" = { TXT = [{ content = "x" }] } }' % LONG],
     MESSAGES['long_names'] + '"%s.example.com" (267 characters) from records["%s"]["TXT"][0]' % (LONG, LONG)),
    ('self_cnames',
     ['records = { "www" = { CNAME = [{ content = "www" }] } }'],
     MESSAGES['self_cnames'] + '"www CNAME" from records["www"]["CNAME"][0]'),
    ('not_owned',
     ['owned_names = { include = ["apps"], exclude = ["k8s.apps"] }', 'records = { "app" = { A = [{ content = "192.0.2.1" }] } }'],
     MESSAGES['not_owned'].format(include='apps.example.com', exclude='k8s.apps.example.com') + '"app.example.com" (A) from records["app"]["A"][0]'),
    ('cname_conflicts',
     ['records = { "app" = { CNAME = [{ content = "target.example.net" }], A = [{ content = "192.0.2.1" }] } }'],
     MESSAGES['cname_conflicts'] + '"app.example.com": A from records["app"]["A"][0], CNAME from records["app"]["CNAME"][0]'),
]


def run(command, directory):
    # show and test have no -input
    flags = ['-input=false', '-no-color'] if command[0] in ('plan', 'apply') else ['-no-color']
    # Flags before the arguments: apply takes the plan file last
    result = subprocess.run([terraform, command[0], *flags, *command[1:]], cwd=directory, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def init(directory):
    subprocess.run([terraform, 'init', '-backend=false', '-input=false', '-no-color'], cwd=directory, check=True, stdout=subprocess.DEVNULL)


def matches(expected, code, output):
    return code == 0 if expected is None else code != 0 and expected in output


def failed_with(result, message):
    """Whether the -json output of plan, apply or test has the error of a check with this
    message (without the line that names the validation rule)"""
    code, output = result
    for line in output.splitlines():
        try:
            diagnostic = json.loads(line).get('diagnostic') or {}
        except (ValueError, AttributeError):
            continue
        if (code != 0 and diagnostic.get('severity') == 'error' and diagnostic.get('summary') == 'Invalid value for variable'
                and diagnostic.get('detail', '').split('\n\nThis was checked by')[0] == message):
            return True
    return False


failed = []


def report(name, ok, output):
    print(f'{"ok  " if ok else "FAIL"} {name}')
    if not ok:
        print(output)
        failed.append(name)


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
  for_each = nonsensitive(module.dns.records)
}
''' % arguments)
        (directory / 'terraform.tfstate').unlink(missing_ok=True)
        init(directory)
        code, output = run(['plan'], directory)
        ok = matches(expected_plan, code, output)
        if ok and expected_apply is not False:
            code, output = run(['apply', '-auto-approve'], directory)
            ok = matches(expected_apply, code, output)
        report(name, ok, output)

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

# The records output of root, v5, v4, idna and compile is sensitive in the plan JSON of the
# module as a root module (a caller must mark its own output, and Terraform 1.9.0 does not
# carry the mark through a module call), record_metadata is not. The provider gets a
# made-up token: the plan reads nothing from Cloudflare
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

# The v4 wrapper with a content known only after apply (plan only: the provider gets a
# made-up token and creates nothing): the keys of the records stay known at plan, so
# for_each works, with an explicit key and with the normalized key of a known value. A
# zone known only after apply is not for the wrappers (the lookup of the zone is a count,
# as in the v5 wrapper); compile covers it above
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
''')
    init(directory)
    code, output = run(['plan', '-out=tfplan'], directory)
    shown = run(['show', '-json', 'tfplan'], directory)
    try:
        keys = sorted(c['index'] for c in json.loads(shown[1])['resource_changes'] if c['type'] == 'cloudflare_record')
    except (ValueError, KeyError):
        keys = []
    report('v4: keys known at plan with a content known after apply', code == 0 and keys == ['alias CNAME', 'web A 192.0.2.2', 'web A web'], output + str(keys))

# Switching from the v4 wrapper to the v5 wrapper (docs/upgrading.md) with the file of moved
# blocks of the v4 step left in place after its apply: the blocks name addresses that the
# v5 wrapper has no resource at, and Terraform leaves them alone, without a change or an
# error. Recorded here so a change of that behavior in Terraform shows up; the docs still
# tell to delete the file after apply
with tempfile.TemporaryDirectory(prefix='.plan-checks-', dir=ROOT) as tmp:
    directory = Path(tmp)
    (directory / 'main.tf').write_text('''terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

module "dns" {
  source    = "../modules/dns/v5"
  zone_id   = "z"
  zone_name = "example.com"
  records   = { "www" = { A = [{ content = "192.0.2.1" }] } }
}
''')
    (directory / 'dns_migration.tf').write_text('''moved {
  from = module.dns.cloudflare_record.record["WWW A 192.0.2.1"]
  to   = module.dns.cloudflare_record.record["www A 192.0.2.1"]
}
''')
    init(directory)
    code, output = run(['plan', '-out=tfplan'], directory)
    shown = run(['show', '-json', 'tfplan'], directory)
    try:
        changes = [c for c in json.loads(shown[1])['resource_changes'] if c['type'] == 'cloudflare_dns_record']
        ok = code == 0 and [c['change']['actions'] for c in changes] == [['create']] and not any(c.get('previous_address') for c in changes)
    except (ValueError, KeyError):
        ok = False
    report('v4 to v5: moved blocks of the v4 step left in place do not fail the plan', ok, output)

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
# Records in other forms (each moves) next to one in the canonical form (stays). The
# explicit key holds template sequences, which the command escapes in the addresses
FORMS = {
    'WWW': {'A': [{'content': '192.0.2.1'}], 'TXT': [{'content': 'v=1', 'key': '${1+1}%{if-true}x'}]},
    'app': {'AAAA': [{'content': '2001:DB8:0:0:0:0:0:1'}]},
    '@': {'MX': [{'content': 'Mail.Example.com.', 'priority': 10}]},
    '_SIP._tcp': {'SRV': [{'data': {'priority': '10.0', 'weight': 5, 'port': 5060, 'target': 'sip.example.com'}}]},
    'static': {'A': [{'content': '192.0.2.2'}]},
}
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

if failed:
    raise SystemExit(f'Failed: {", ".join(failed)}')
