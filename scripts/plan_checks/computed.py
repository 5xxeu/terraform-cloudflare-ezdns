"""Values known only after apply in the input of the module (plan, and apply when the plan passes)"""

from pathlib import Path
import tempfile

from .helpers import ROOT, TTL, VALUE, init, matches, report, run


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
    # Where a known violation and a value known only after apply meet: a computed attribute
    # that applies to its type is not looked at, so the known violation fails at plan; next
    # to a computed attribute that does not apply, the known violation in an earlier name
    # still fails at plan (alltrue stops at the first false) and in a later name the check
    # waits for apply (the matrix of the unused attribute rule; the same on both Terraform
    # versions, the cases inside one record differ between them and are not listed). The
    # text of the plan error next to a computed attribute that does not apply is not
    # stable (Terraform cannot evaluate the message there), only that the plan fails
    ('records: known violation, then a computed attribute that applies',
     'records = { "a" = { A = [{ content = "192.0.2.1", priority = 10 }] }, "b" = { MX = [{ content = "m.example.net", priority = %s }] } }' % TTL,
     'records["a"]["A"][0].priority', False),
    ('records: a computed attribute that applies, then a known violation',
     'records = { "a" = { MX = [{ content = "m.example.net", priority = %s }] }, "b" = { A = [{ content = "192.0.2.1", priority = 10 }] } }' % TTL,
     'records["b"]["A"][0].priority', False),
    ('records: known violation, then a computed attribute that does not apply',
     'records = { "a" = { A = [{ content = "192.0.2.1", priority = 10 }] }, "b" = { A = [{ content = "192.0.2.2", priority = %s }] } }' % TTL,
     'Invalid', False),
    ('records: computed attribute that does not apply, then a known violation (put off until apply)',
     'records = { "a" = { A = [{ content = "192.0.2.2", priority = %s }] }, "b" = { A = [{ content = "192.0.2.1", priority = 10 }] } }' % TTL,
     None, 'records["a"]["A"][0].priority'),
    ('records: computed attributes that apply and that do not',
     'records = { "c" = { MX = [{ content = "m.example.net", priority = %s }] }, "a" = { A = [{ content = "192.0.2.2", priority = %s }] } }' % (TTL, TTL),
     None, 'records["a"]["A"][0].priority'),
    ('records: only a computed attribute that applies',
     'records = { "b" = { MX = [{ content = "m.example.net", priority = %s }] } }' % TTL,
     None, None),
    ('record_groups: known violation, then a computed attribute that applies',
     'record_groups = { web = { records = { "a" = { A = [{ content = "192.0.2.1", priority = 10 }] }, "b" = { MX = [{ content = "m.example.net", priority = %s }] } } } }' % TTL,
     'record_groups["web"].records["a"]["A"][0].priority', False),
    ('record_groups: a computed attribute that applies, then a known violation',
     'record_groups = { web = { records = { "a" = { MX = [{ content = "m.example.net", priority = %s }] }, "b" = { A = [{ content = "192.0.2.1", priority = 10 }] } } } }' % TTL,
     'record_groups["web"].records["b"]["A"][0].priority', False),
    ('record_groups: known violation, then a computed attribute that does not apply',
     'record_groups = { web = { records = { "a" = { A = [{ content = "192.0.2.1", priority = 10 }] }, "b" = { A = [{ content = "192.0.2.2", priority = %s }] } } } }' % TTL,
     'Invalid', False),
    ('record_groups: computed attribute that does not apply, then a known violation (put off until apply)',
     'record_groups = { web = { records = { "a" = { A = [{ content = "192.0.2.2", priority = %s }] }, "b" = { A = [{ content = "192.0.2.1", priority = 10 }] } } } }' % TTL,
     None, 'record_groups["web"].records["a"]["A"][0].priority'),
    ('record_groups: computed attributes that apply and that do not',
     'record_groups = { web = { records = { "c" = { MX = [{ content = "m.example.net", priority = %s }] }, "a" = { A = [{ content = "192.0.2.2", priority = %s }] } } } }' % (TTL, TTL),
     None, 'record_groups["web"].records["a"]["A"][0].priority'),
    ('record_groups: only a computed attribute that applies',
     'record_groups = { web = { records = { "b" = { MX = [{ content = "m.example.net", priority = %s }] } } } }' % TTL,
     None, None),
    # Expected: without a key, a record is keyed by its value, so a value known only
    # after apply makes its key unknown and the resources cannot be planned
    ('content known after apply, without a key',
     'records = { "@" = { A = [{ content = %s }] } }' % VALUE,
     'Invalid for_each argument', False),
]


def main():
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
