"""What the groups of scripts/test-plan-checks.py share: the repository root, the
Terraform binary, the commands, the texts of the checks and the report of the results"""
import json
import os
from pathlib import Path
import subprocess

# The only place that knows where the repository is (scripts/plan_checks/helpers.py)
ROOT = Path(__file__).resolve().parents[2]
terraform = os.environ.get('TERRAFORM', 'terraform')

# A TTL and a text value from another resource are unknown at plan
TTL = 'tonumber(terraform_data.ttl.output)'
VALUE = 'terraform_data.value.output'

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
