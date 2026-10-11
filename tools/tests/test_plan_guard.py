"""Tests of plan-guard.py with plans in the JSON format of terraform show -json.

    python3 -m unittest discover -s tools/tests
"""

import importlib.util
import json
import pathlib
import tempfile
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
    return {"format_version": "1.2", "planned_values": {}, "resource_changes": list(changes)}


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

    def test_proxy_disable_in_a_replacement_fails(self):
        # Allowing the replacement does not allow the record to come back unproxied
        p = plan(record(BASE.format("web A 192.0.2.1"), ["delete", "create"], WEB, {**WEB, "proxied": False}))
        problems = run(p, "--max-replacements", "1")
        self.assertIn("turns off the proxy", problems[0])

    def test_proxy_disable_through_a_new_key_fails(self):
        # A changed value without a key: the proxied record is deleted, an unproxied one
        # is created on the same name
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z", "name": "web.example.com"}, None),
            record(BASE.format("web A 192.0.2.9"), ["create"], None, {**WEB, "zone_id": "z", "content": "192.0.2.9", "proxied": False}),
        )
        problems = run(p, "--max-deletes", "1")
        self.assertIn("turns off the proxy", problems[0])
        self.assertIn("192.0.2.9", problems[1])
        self.assertEqual(run(p, "--max-deletes", "1", "--allow-proxy-disable"), [])

    def test_new_key_that_stays_proxied_passes(self):
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web A 192.0.2.9"), ["create"], None, {**WEB, "zone_id": "z", "content": "192.0.2.9"}),
            record(BASE.format("other A 192.0.2.8"), ["create"], None, {**WEB, "zone_id": "z", "name": "other", "proxied": False}),
        )
        self.assertEqual(run(p, "--max-deletes", "1", "--zone", "example.com"), [])

    def test_proxied_delete_is_not_a_proxy_disable(self):
        p = plan(record(BASE.format("web A 192.0.2.1"), ["delete"], WEB, None))
        self.assertEqual(run(p, "--max-deletes", "1"), [])

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

    def test_required_set_ignores_unknown_names(self):
        # A name computed at apply is not proven to be the apex
        after = {k: v for k, v in MX.items() if k != "name"}
        p = plan(record(BASE.format("@ MX mx.example.com"), ["create"], None, after, {"name": True}))
        self.assertIn("0 after the apply", run(p, "--zone", "example.com", "--require", "@:MX")[0])

    def test_required_set_of_several_zones(self):
        # The MX of another zone must not count for this one
        other = {**MX, "zone_id": "other"}
        p = plan(
            record(BASE.format("@ MX mx.example.com"), ["delete"], {**MX, "zone_id": "z"}, None),
            record('module.other.cloudflare_dns_record.record["@ MX mx.example.com"]', ["no-op"], other, other),
        )
        problems = run(p, "--max-deletes", "1", "--zone", "example.com", "--require", "@:MX")
        self.assertIn("several zones", "\n".join(problems))
        problems = run(p, "--max-deletes", "1", "--zone", "example.com", "--zone-id", "z", "--require", "@:MX")
        self.assertEqual(problems, ["MX records of example.com: 0 after the apply, at least 1 required"])
        self.assertEqual(run(p, "--max-deletes", "1", "--zone", "example.com", "--zone-id", "other", "--require", "@:MX"), [])

    def test_required_minimum(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["no-op"], MX, MX))
        self.assertIn("at least 2 required", run(p, "--zone", "example.com", "--require", "@:MX:2")[0])

    def test_module_filter(self):
        p = plan(record('module.other.cloudflare_dns_record.record["x"]', ["delete"], MX, None))
        self.assertEqual(run(p, "--module", "module.dns"), [])
        self.assertNotEqual(run(p), [])

    def test_module_filter_with_instances(self):
        # module calls with count or for_each have instance keys
        p = plan(
            record('module.dns[0].cloudflare_dns_record.record["web A 192.0.2.1"]', ["update"], WEB, {**WEB, "proxied": False}),
            record('module.dns["prod"].cloudflare_dns_record.record["x"]', ["delete"], MX, None),
            record('module.dnsx.cloudflare_dns_record.record["y"]', ["delete"], MX, None),
        )
        problems = run(p, "--module", "module.dns")
        self.assertIn("deletes 1 records", problems[0])
        self.assertTrue(any("turns off the proxy" in x for x in problems))
        self.assertEqual(run(p, "--module", 'module.dns["prod"]', "--max-deletes", "1"), [])

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


class MainTest(unittest.TestCase):
    def exit_code(self, document):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(document, f)
        try:
            return plan_guard.main([f.name])
        finally:
            pathlib.Path(f.name).unlink()

    def test_plan_without_changes_passes(self):
        # terraform show -json of a plan without changes has no resource_changes
        self.assertEqual(self.exit_code({"format_version": "1.2", "planned_values": {}}), 0)

    def test_state_is_not_a_plan(self):
        # terraform show -json without the plan file prints the state
        self.assertEqual(self.exit_code({"format_version": "1.0", "values": {}}), 2)
        self.assertEqual(self.exit_code({"format_version": "1.0"}), 2)

    def test_failing_plan(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["delete"], MX, None))
        self.assertEqual(self.exit_code(p), 1)


if __name__ == "__main__":
    unittest.main()
