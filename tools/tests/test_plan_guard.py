"""Tests of plan-guard.py with plans in the JSON format of terraform show -json.

    python3 -m unittest discover -s tools/tests
"""

import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
import unittest.mock

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

    def test_proxy_disable_through_another_type_fails(self):
        # A proxied CNAME deleted, an unproxied A created on the same name
        cname = {"name": "web", "type": "CNAME", "content": "lb.example.net", "proxied": True, "zone_id": "z"}
        p = plan(
            record(BASE.format("web CNAME"), ["delete"], cname, None),
            record(BASE.format("web A 192.0.2.9"), ["create"], None, {**WEB, "zone_id": "z", "content": "192.0.2.9", "proxied": False}),
        )
        self.assertIn("turns off the proxy", run(p, "--max-deletes", "1")[0])

    def test_allowed_delete_does_not_allow_an_unproxied_successor(self):
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web A 192.0.2.9"), ["create"], None, {**WEB, "zone_id": "z", "content": "192.0.2.9", "proxied": False}),
        )
        problems = run(p, "--allow", BASE.format("web A 192.0.2.1"))
        self.assertIn("turns off the proxy", problems[0])

    def test_unknown_zone_of_an_unproxied_successor_fails(self):
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web A 192.0.2.9"), ["create"], None, {**WEB, "content": "192.0.2.9", "proxied": False}, {"zone_id": True}),
        )
        self.assertIn("turns off the proxy", run(p, "--max-deletes", "1")[0])

    def test_unproxied_record_moved_onto_the_name_fails(self):
        # An existing unproxied record renamed by an update onto the name of a deleted proxied one
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("old A 192.0.2.9"), ["update"], {**WEB, "zone_id": "z", "name": "old", "proxied": False},
                   {**WEB, "zone_id": "z", "content": "192.0.2.9", "proxied": False}),
        )
        self.assertIn("turns off the proxy", run(p, "--max-deletes", "1")[0])

    def test_unproxied_record_left_without_proxied_neighbours_fails(self):
        # While a proxied A was on the name, Cloudflare answered for the whole name; without
        # it the unproxied AAAA (unchanged, no-op) publishes its address
        aaaa = {"name": "web", "type": "AAAA", "content": "2001:db8::1", "proxied": False, "zone_id": "z"}
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web AAAA 2001:db8::1"), ["no-op"], aaaa, aaaa),
        )
        self.assertIn("turns off the proxy", run(p, "--max-deletes", "1")[0])

    def test_unproxied_record_next_to_a_remaining_proxied_one_passes(self):
        aaaa = {"name": "web", "type": "AAAA", "content": "2001:db8::1", "proxied": False, "zone_id": "z"}
        other = {**WEB, "zone_id": "z", "content": "192.0.2.2"}
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web A 192.0.2.2"), ["no-op"], other, other),
            record(BASE.format("web AAAA 2001:db8::1"), ["update"], aaaa, {**aaaa, "ttl": 300}),
        )
        self.assertEqual(run(p, "--max-deletes", "1"), [])

    def test_apex_in_another_form_without_zone_fails(self):
        apex = {**WEB, "name": "example.com", "zone_id": "z"}
        p = plan(
            record(BASE.format("example.com A 192.0.2.1"), ["delete"], apex, None),
            record(BASE.format("@ A 192.0.2.9"), ["create"], None, {**apex, "name": "@", "content": "192.0.2.9", "proxied": False}),
        )
        self.assertIn("turns off the proxy", run(p, "--max-deletes", "1")[0])

    def test_record_turned_into_an_unproxied_address_fails(self):
        # The same resource replaced from TXT into an unproxied AAAA, next to a deleted proxied A
        txt = {"name": "web", "type": "TXT", "content": "x", "proxied": False, "zone_id": "z"}
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web x"), ["delete", "create"], txt, {**txt, "type": "AAAA", "content": "2001:db8::9"}),
        )
        problems = run(p, "--allow", BASE.format("web A 192.0.2.1"), "--max-replacements", "1")
        self.assertIn("turns off the proxy", problems[0])

    def test_new_content_of_an_unproxied_record_fails(self):
        aaaa = {"name": "web", "type": "AAAA", "content": "2001:db8::1", "proxied": False, "zone_id": "z"}
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web AAAA"), ["update"], aaaa, {**aaaa, "content": "2001:db8::9"}),
        )
        self.assertIn("turns off the proxy", run(p, "--max-deletes", "1")[0])

    def test_text_record_on_the_name_of_a_proxied_record_passes(self):
        p = plan(
            record(BASE.format("web A 192.0.2.1"), ["delete"], {**WEB, "zone_id": "z"}, None),
            record(BASE.format("web TXT x"), ["create"], None, {"name": "web", "type": "TXT", "content": "x", "proxied": False, "zone_id": "z"}),
        )
        self.assertEqual(run(p, "--max-deletes", "1"), [])

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

    def test_unreadable_plan_and_bad_arguments(self):
        # 2, not 1: a broken input must not pass where 1 (a failing plan) is handled
        for argv in (["/nonexistent/plan.json"], ["-", "--require", "@"], ["-", "--require", "@:MX:x"]):
            with self.assertRaises(SystemExit) as e, contextlib.redirect_stderr(io.StringIO()), \
                    unittest.mock.patch("sys.stdin", io.StringIO('{"format_version": "1.2", "planned_values": {}}')):
                plan_guard.main(argv)
            self.assertEqual(e.exception.code, 2)

    def test_unexpected_structure_is_exit_code_2(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.exit_code({"format_version": "1.2", "planned_values": {}, "resource_changes": None}), 2)
            broken = plan(record(BASE.format("web"), ["update"], {**WEB, "proxied": True, "name": 42}, {**WEB, "name": 42, "proxied": False}))
            broken["resource_changes"][0]["change"]["after_unknown"] = []
            self.assertEqual(self.exit_code(broken), 2)

    def test_failing_plan(self):
        p = plan(record(BASE.format("@ MX mx.example.com"), ["delete"], MX, None))
        self.assertEqual(self.exit_code(p), 1)


if __name__ == "__main__":
    unittest.main()
