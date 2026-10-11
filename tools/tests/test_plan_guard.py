"""Tests of plan-guard.py with plans in the JSON format of terraform show -json.

    python3 -m unittest discover -s tools/tests
"""

import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("plan_guard", pathlib.Path(__file__).parent.parent / "plan-guard.py")
plan_guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan_guard)


def record(address, actions, before=None, after=None, after_unknown=None, rtype="cloudflare_dns_record"):
    return {
        "address": address,
        "mode": "managed",
        "type": rtype,
        "change": {"actions": actions, "before": before, "after": after, "after_unknown": after_unknown or {}},
    }


def plan(*changes):
    return {"format_version": "1.2", "resource_changes": list(changes)}


MX = {"name": "@", "type": "MX", "content": "mx.example.com", "proxied": False}
WEB = {"name": "web", "type": "A", "content": "192.0.2.1", "proxied": True}
BASE = 'module.dns.module.v5.cloudflare_dns_record.record["{}"]'


def run(p, *argv):
    args = plan_guard.parse_args(["-", *argv])
    return plan_guard.check(p, args)


class PlanGuardTest(unittest.TestCase):
    def test_no_changes_pass(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["no-op"], MX, MX))
        self.assertEqual(run(p, "--zone", "example.com", "--require", "@:MX"), [])

    def test_delete_fails(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["delete"], MX, None))
        problems = run(p)
        self.assertIn("deletes 1 records", problems[0])

    def test_delete_within_limit_passes(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["delete"], MX, None))
        self.assertEqual(run(p, "--max-deletes", "1"), [])

    def test_replacement_fails_in_both_orders(self):
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete", "create"], WEB, WEB),
            record(BASE.format("app A 192.0.2.2"), ["create", "delete"], WEB, WEB),
        )
        problems = run(p)
        self.assertIn("replaces 2 records", problems[0])

    def test_value_change_without_key_is_a_delete(self):
        # A changed value gives the record a new key: one delete and one create
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], WEB, None),
            record(BASE.format("web A 192.0.2.9"), ["create"], None, {**WEB, "content": "192.0.2.9"}),
        )
        self.assertIn("deletes 1 records", run(p)[0])

    def test_allow_pattern(self):
        p = plan(record(BASE.format("web A 192.0.2.1"), ["delete"], WEB, None))
        self.assertEqual(run(p, "--allow", 'module.dns.*["web A *"]'), [])

    def test_proxy_disable_fails(self):
        p = plan(record(BASE.format("web A 192.0.2.1"), ["update"], WEB, {**WEB, "proxied": False}))
        self.assertIn("turns off the proxy", run(p)[0])
        self.assertEqual(run(p, "--allow-proxy-disable"), [])

    def test_unknown_proxy_fails(self):
        p = plan(record(BASE.format("web A 192.0.2.1"), ["update"], WEB, {**WEB, "proxied": None}, {"proxied": True}))
        self.assertIn("not known until apply", run(p)[0])

    def test_required_set_emptied(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["delete"], MX, None))
        problems = run(p, "--max-deletes", "5", "--zone", "example.com", "--require", "@:MX")
        self.assertEqual(problems, ["MX records of example.com: 0 after the apply, at least 1 required"])

    def test_required_set_with_fully_qualified_names(self):
        after = {**MX, "name": "example.com"}
        p = plan(record(BASE.format("@ MX mx.example.com"), ["update"], MX, after))
        self.assertEqual(run(p, "--zone", "example.com.", "--require", "example.com:mx:1"), [])

    def test_required_minimum(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["no-op"], MX, MX))
        self.assertIn("at least 2 required", run(p, "--zone", "example.com", "--require", "@:MX:2")[0])

    def test_module_filter(self):
        p = plan(record('module.other.cloudflare_dns_record.record["x"]', ["delete"], MX, None))
        self.assertEqual(run(p, "--module", "module.dns"), [])
        self.assertNotEqual(run(p), [])

    def test_other_resources_ignored(self):
        p = plan({"address": "cloudflare_zone.z", "mode": "managed", "type": "cloudflare_zone",
                  "change": {"actions": ["delete"], "before": {}, "after": None}})
        self.assertEqual(run(p), [])

    def test_provider_v4(self):
        p = plan(record('module.dns.cloudflare_record.record["@ MX mx.example.com"]', ["delete"], MX, None, rtype="cloudflare_record"))
        self.assertIn("deletes 1 records", run(p)[0])

    def test_require_needs_zone(self):
        with self.assertRaises(SystemExit):
            plan_guard.parse_args(["-", "--require", "@:MX"])

    def test_bad_require(self):
        with self.assertRaises(SystemExit):
            run(plan(), "--zone", "example.com", "--require", "MX")


if __name__ == "__main__":
    unittest.main()
