"""Tests of zone-to-ezdns.py with the records of fixtures/zone.json (Cloudflare API form).

    python3 -m unittest discover -s tools/tests
"""

import importlib.util
import json
import pathlib
import unittest

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("zone_to_ezdns", HERE.parent / "zone-to-ezdns.py")
z = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z)

ZONE = json.loads((HERE / "fixtures" / "zone.json").read_text())["result"]


class ConvertTest(unittest.TestCase):
    def setUp(self):
        self.records, self.notes = z.convert(ZONE, "example.com", 3600)

    def test_names_relative_to_the_zone(self):
        self.assertEqual(sorted(self.records), ["@", "_dmarc", "_sip._tcp", "dup", "off", "www"])

    def test_proxied_without_ttl(self):
        self.assertEqual(self.records["@"]["A"], [{"content": "192.0.2.1", "proxied": True, "comment": "web", "tags": ["team:web"]}])

    def test_ttl_only_when_not_the_default(self):
        self.assertEqual(self.records["@"]["TXT"], [{"content": "\"v=spf1 mx -all\"", "ttl": 300}])
        self.assertNotIn("ttl", self.records["_dmarc"]["TXT"][0])

    def test_mx_that_differ_only_in_priority_get_keys(self):
        self.assertEqual([r["key"] for r in self.records["@"]["MX"]], ["priority-10", "priority-20"])

    def test_keys_unique_across_targets(self):
        # Two MX targets with the same pair of priorities: priority-10 alone would repeat
        mx = [{"id": str(i), "name": "example.com", "type": "MX", "content": t, "priority": p, "proxied": False, "ttl": 3600}
              for i, (t, p) in enumerate([("mx1.example.com", 10), ("mx1.example.com", 20), ("mx2.example.com", 10), ("mx2.example.com", 20)])]
        records, notes = z.convert(mx, "example.com", 3600)
        self.assertEqual([r["key"] for r in records["@"]["MX"]], [
            "mx1.example.com-priority-10", "mx1.example.com-priority-20", "mx2.example.com-priority-10", "mx2.example.com-priority-20",
        ])
        self.assertEqual(notes, [])

    def test_copies_with_another_ttl_written_once(self):
        # TTL and comment are not part of what the record is: still copies of one record
        mx = [{"id": str(i), "name": "example.com", "type": "MX", "content": "mx.example.com", "priority": 10, "proxied": False, "ttl": ttl}
              for i, ttl in enumerate([3600, 300])]
        records, notes = z.convert(mx, "example.com", 3600)
        self.assertEqual(records["@"]["MX"], [{"content": "mx.example.com", "priority": 10}])
        self.assertTrue(any("2 copies of MX @" in n for n in notes))

    def test_caa_from_data(self):
        self.assertEqual(self.records["@"]["CAA"][1], {"content": "letsencrypt.org", "tag": "issue", "flags": 128, "key": "flags-128"})

    def test_srv_data_without_extra_fields(self):
        self.assertEqual(self.records["_sip._tcp"]["SRV"], [{"data": {"priority": "10", "weight": "5", "port": "5060", "target": "sip.example.com"}}])

    def test_copies_written_once(self):
        self.assertEqual(self.records["dup"]["A"], [{"content": "192.0.2.5"}])
        self.assertTrue(any("2 copies of A dup" in n for n in self.notes))

    def test_skipped(self):
        joined = "\n".join(self.notes)
        self.assertIn("read only", joined)
        self.assertIn("not in the zone", joined)
        self.assertIn("does not support SPF", joined)

    def test_unmanaged_records_form_needs_a_check_of_proxied(self):
        records, notes = z.convert([{"id": "x", "name": "web.example.com", "type": "A", "content": "192.0.2.7", "priority": None, "data": None}], "example.com", 3600)
        self.assertEqual(records, {"web": {"A": [{"content": "192.0.2.7"}]}})
        self.assertTrue(any("proxied" in n for n in notes))


class YamlTest(unittest.TestCase):
    def test_values_are_quoted(self):
        records, _ = z.convert(ZONE, "example.com", 3600)
        out = z.to_yaml(records, "example.com", 0)
        # "off" stays a string in YAML 1.1, numbers of data stay text
        self.assertIn('      - content: "off"', out)
        self.assertIn('          port: "5060"', out)
        self.assertIn('  "@":', out)
        self.assertTrue(out.splitlines()[3] == "records:")

    def test_apex_first(self):
        records, _ = z.convert(ZONE, "example.com", 3600)
        names = [line.strip()[:-1] for line in z.to_yaml(records, "example.com", 0).splitlines() if line.startswith("  \"")]
        self.assertEqual(names[0], '"@"')


if __name__ == "__main__":
    unittest.main()
