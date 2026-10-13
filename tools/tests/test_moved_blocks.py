"""Tests of moved-blocks.py with plans in the JSON format of terraform show -json.

    python3 -m unittest discover -s tools/tests
"""

import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("moved_blocks", pathlib.Path(__file__).parent.parent / "moved-blocks.py")
moved_blocks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(moved_blocks)

BASE = 'module.dns.module.v5.cloudflare_dns_record.record["{}"]'


def record(key, actions, before=None, after=None, after_unknown=None, rtype="cloudflare_dns_record"):
    return {
        "address": BASE.format(key) if rtype == "cloudflare_dns_record" else f'module.dns.cloudflare_record.record["{key}"]',
        "mode": "managed",
        "type": rtype,
        "change": {"actions": actions, "before": before, "after": after, "after_unknown": after_unknown or {}},
    }


def plan(*changes):
    return {"format_version": "1.2", "planned_values": {}, "resource_changes": list(changes)}


def run(p):
    out, err = io.StringIO(), io.StringIO()
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(p, f)
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = moved_blocks.main([f.name, "--zone", "example.com"])
    pathlib.Path(f.name).unlink()
    return code, out.getvalue()


A = {"zone_id": "z", "name": "www", "type": "A", "content": "192.0.2.1", "proxied": True}


class MovedBlocksTest(unittest.TestCase):
    def test_new_key_of_the_same_record_is_moved(self):
        # A key added: the same record under another address, also with a name in
        # another form and another TTL
        p = plan(
            record("www A 192.0.2.1", ["delete"], A, None),
            record("www A web", ["create"], None, {**A, "name": "WWW.example.com.", "ttl": 300}),
        )
        code, out = run(p)
        self.assertEqual(code, 0)
        self.assertEqual(out, 'moved {\n  from = %s\n  to   = %s\n}\n' % (BASE.format("www A 192.0.2.1"), BASE.format("www A web")))

    def test_another_value_is_not_moved(self):
        p = plan(
            record("www A 192.0.2.1", ["delete"], A, None),
            record("www A 192.0.2.2", ["create"], None, {**A, "content": "192.0.2.2"}),
        )
        self.assertEqual(run(p), (0, ""))

    def test_addresses_and_hostnames_in_another_form_match(self):
        aaaa = {"zone_id": "z", "name": "@", "type": "AAAA", "content": "2001:db8:0:0::1"}
        mx = {"zone_id": "z", "name": "@", "type": "MX", "content": "Mx.Example.com.", "priority": 10}
        p = plan(
            record("@ AAAA 2001:db8:0:0::1", ["delete"], aaaa, None),
            record("@ AAAA v6", ["create"], None, {**aaaa, "name": "example.com", "content": "2001:db8::1"}),
            record("@ MX mx.example.com", ["delete"], mx, None),
            record("@ MX primary", ["create"], None, {**mx, "content": "mx.example.com", "priority": 10.0}),
        )
        code, out = run(p)
        self.assertEqual(code, 0)
        self.assertEqual(out.count("moved {"), 2)

    def test_txt_in_the_zone_file_form_matches_its_text(self):
        txt = {"zone_id": "z", "name": "@", "type": "TXT"}
        for old, new, moved in (('"v=spf1 \\"a\\" -all"', 'v=spf1 "a" -all', 1), ('"v=spf1 " "-all"', "v=spf1 -all", 1),
                                ('"\\065"', "A", 0), ('a" "b', "ab", 0)):
            p = plan(record("@ TXT a", ["delete"], {**txt, "content": old}, None),
                     record("@ TXT b", ["create"], None, {**txt, "content": new}))
            self.assertEqual(run(p)[1].count("moved {"), moved, old)

    def test_hex_certificates_and_caa_issuers_in_any_case(self):
        tlsa = {"zone_id": "z", "name": "_443._tcp", "type": "TLSA", "data": {"usage": 3, "selector": 1, "matching_type": 1, "certificate": "ABCD"}}
        caa = {"zone_id": "z", "name": "@", "type": "CAA", "data": {"flags": 0, "tag": "issue", "value": "LetsEncrypt.org; accounturi=https://x/A"}}
        for old, new, moved in ((tlsa, {**tlsa, "data": {**tlsa["data"], "certificate": "abcd"}}, 1),
                                (caa, {**caa, "data": {**caa["data"], "value": "letsencrypt.org; accounturi=https://x/A"}}, 1),
                                (caa, {**caa, "data": {**caa["data"], "value": "LetsEncrypt.org; accounturi=https://x/a"}}, 0)):
            p = plan(record("a", ["delete"], old, None), record("b", ["create"], None, new))
            self.assertEqual(run(p)[1].count("moved {"), moved, new)

    def test_uri_target_compared_exactly(self):
        uri = {"zone_id": "z", "name": "_http._tcp", "type": "URI", "priority": 10,
               "data": {"weight": 1, "target": "https://example.com/Admin"}}
        other = {**uri, "data": {"weight": 1, "target": "https://example.com/admin"}}
        p = plan(record("a", ["delete"], uri, None), record("b", ["create"], None, other))
        self.assertEqual(run(p), (0, ""))

    def test_priority_and_zone_are_part_of_the_record(self):
        mx = {"zone_id": "z", "name": "@", "type": "MX", "content": "mx.example.com", "priority": 10}
        p = plan(
            record("@ MX mx.example.com", ["delete"], mx, None),
            record("@ MX a", ["create"], None, {**mx, "priority": 20}),
            record("@ MX b", ["create"], None, {**mx, "zone_id": "other"}),
        )
        self.assertEqual(run(p), (0, ""))

    def test_data_records_match_in_both_provider_forms(self):
        srv = {"zone_id": "z", "name": "_sip._tcp", "type": "SRV", "priority": 10,
               "data": {"priority": 10, "weight": 5, "port": 5060, "target": "SIP.example.com."}}
        p = plan(
            record("_sip._tcp SRV abc", ["delete"], {**srv, "content": "5 5060 sip.example.com"}, None),
            record("_sip._tcp SRV sip", ["create"], None, {**srv, "data": {**srv["data"], "target": "sip.example.com"}}),
        )
        self.assertEqual(run(p)[1].count("moved {"), 1)
        v4 = {**srv, "data": [srv["data"]]}
        p = plan(record("a", ["delete"], v4, None, rtype="cloudflare_record"), record("b", ["create"], None, v4, rtype="cloudflare_record"))
        self.assertEqual(run(p)[1].count("moved {"), 1)

    def test_copies_need_a_choice(self):
        p = plan(
            record("www A 192.0.2.1", ["delete"], A, None),
            record("www A a", ["create"], None, A),
            record("www A b", ["create"], None, A),
        )
        code, out = run(p)
        self.assertEqual(code, 1)
        self.assertNotIn("moved {", out)
        self.assertIn("1 deleted and 2 created", out)

    def test_unknown_value_needs_a_choice(self):
        p = plan(
            record("www A 192.0.2.1", ["delete"], A, None),
            record("www A ip", ["create"], None, {k: v for k, v in A.items() if k != "content"}, {"content": True}),
        )
        code, out = run(p)
        self.assertEqual(code, 1)
        self.assertIn("known only after apply", out)

    def test_content_computed_from_a_known_data_is_paired(self):
        # Provider 5.x computes the content of an SRV from its data: unknown at plan
        srv = {"zone_id": "z", "name": "_sip._tcp", "type": "SRV", "data": {"priority": 10, "weight": 5, "port": 5060, "target": "sip.example.com"}}
        p = plan(
            record("_sip._tcp SRV a", ["delete"], {**srv, "content": "5 5060 sip.example.com"}, None),
            record("_sip._tcp SRV b", ["create"], None, srv, {"content": True, "data": {}}),
        )
        self.assertEqual(run(p)[0], 0)
        self.assertEqual(run(p)[1].count("moved {"), 1)
        # A part of the data unknown, also in the list of provider 4.x: decided by hand
        p = plan(record("a", ["delete"], srv, None), record("b", ["create"], None, srv, {"data": {"target": True}}))
        self.assertEqual(run(p)[0], 1)
        p = plan(record("a", ["delete"], srv, None, rtype="cloudflare_record"),
                 record("b", ["create"], None, srv, {"data": [{"target": True}]}, rtype="cloudflare_record"))
        self.assertEqual(run(p)[0], 1)

    def test_provider_types_are_not_paired(self):
        p = plan(record("a", ["delete"], A, None, rtype="cloudflare_record"), record("b", ["create"], None, A))
        self.assertEqual(run(p), (0, ""))

    def test_bad_input_is_exit_code_2(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(run({"values": {}})[0], 2)
            self.assertEqual(run({"format_version": "1.2", "planned_values": {}, "resource_changes": [{"address": 1}]})[0], 2)


if __name__ == "__main__":
    unittest.main()
