# Conversion of internationalized names before the v5 wrapper. The idna provider is the
# real one (functions only, no configuration); the Cloudflare provider is mocked.

mock_provider "cloudflare" {
  override_data {
    target = data.cloudflare_zone.this[0]
    values = { name = "münchen.de" }
  }
}

variables {
  zone_id   = "z"
  zone_name = "münchen.de"
  records = {
    "@" = {
      A               = [{ content = "192.0.2.1" }]
      "straße.A"      = [{ content = "192.0.2.2" }]
      MX              = [{ content = "mx.münchen.de", priority = 10 }]
      ALIASES         = [{ content = "www" }, { content = "größe" }]
      "_sip._tcp.SRV" = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.münchen.de" } }]
      "_ftp._tcp.URI" = [
        { priority = 10, data = { weight = 1, target = "https://straße.münchen.de/Pfad?ä=1" } },
        { priority = 20, data = { weight = 1, target = "ftp://user:pass@bücher.münchen.de:21/" } },
      ]
      "_naptr.NAPTR"    = [{ data = { order = 100, preference = 10, replacement = "_sip._udp.münchen.de" } }]
      "_dmarc.TXT"      = [{ content = "v=DMARC1; p=reject; rua=mailto:dmarc@münchen.de" }]
      "Upper.CNAME"     = [{ content = "Target.Example.com" }]
      "xn--caf-dma.TXT" = [{ content = "punycode written by hand" }]
    }
    "bücher" = { CNAME = [{ content = "www.münchen.de" }] }
  }
}

run "converted" {
  command = plan

  assert {
    condition     = module.v5.records["xn--bcher-kva CNAME"].content == "www.xn--mnchen-3ya.de"
    error_message = "Names and CNAME targets must be converted to Punycode"
  }

  assert {
    condition     = contains(keys(module.v5.records), "xn--strae-oqa A 192.0.2.2")
    error_message = "Prefixes of record types must be converted"
  }

  assert {
    condition     = contains(keys(module.v5.records), "@ MX mx.xn--mnchen-3ya.de") && length([for k in keys(module.v5.records) : k if startswith(k, "xn--") && endswith(k, " CNAME")]) == 2
    error_message = "MX targets and ALIASES must be converted"
  }

  assert {
    condition     = [for r in module.v5.records : r.data.target if r.type == "SRV"] == ["sip.xn--mnchen-3ya.de"]
    error_message = "SRV targets must be converted"
  }

  assert {
    condition     = sort([for r in module.v5.records : r.data.target if r.type == "URI"]) == tolist(["ftp://user:pass@xn--bcher-kva.xn--mnchen-3ya.de:21/", "https://xn--strae-oqa.xn--mnchen-3ya.de/Pfad?ä=1"])
    error_message = "Only the host of a URI target is converted, also after user information"
  }

  assert {
    condition     = [for r in module.v5.records : r.data.replacement if r.type == "NAPTR"] == ["_sip._udp.xn--mnchen-3ya.de"]
    error_message = "NAPTR replacements must be converted"
  }

  assert {
    condition     = [for r in module.v5.records : r.fqdn if r.type == "TXT" && startswith(r.fqdn, "_dmarc")] == ["_dmarc.xn--mnchen-3ya.de"]
    error_message = "The zone name must be converted"
  }

  assert {
    condition     = contains(keys(module.v5.records), "Upper CNAME") && [for k, r in module.v5.records : r.content if k == "Upper CNAME"] == ["Target.Example.com"]
    error_message = "ASCII names and targets must stay as written, so their keys do not change"
  }

  assert {
    condition     = contains(keys(module.v5.records), "xn--caf-dma TXT ${substr(sha1("punycode written by hand"), 0, 12)}")
    error_message = "Names already in Punycode must stay as written"
  }
}

run "same_keys_as_punycode" {
  command = plan

  variables {
    records = { "bücher" = { A = [{ content = "192.0.2.1" }] } }
  }

  assert {
    condition     = keys(module.v5.records) == ["xn--bcher-kva A 192.0.2.1"]
    error_message = "A name in Unicode must get the key of the name in Punycode in lower case"
  }
}

run "zone_looked_up_in_unicode" {
  command = plan

  variables {
    zone_name = null
    records   = { "@" = { A = [{ content = "192.0.2.1" }] } }
  }

  assert {
    condition     = [for r in module.v5.records : r.fqdn] == ["xn--mnchen-3ya.de"]
    error_message = "The looked-up zone name must be converted"
  }
}

run "record_groups_and_owned_names" {
  command = plan

  variables {
    records       = {}
    record_groups = { shop = { defaults = { ttl = 300 }, records = { "läden" = { A = [{ content = "192.0.2.3" }] } } } }
    owned_names   = { include = ["läden"] }
  }

  assert {
    condition     = keys(module.v5.records) == ["xn--lden-loa A 192.0.2.3"] && module.v5.records["xn--lden-loa A 192.0.2.3"].ttl == 300
    error_message = "Grouped records and owned_names must be converted"
  }
}

run "invalid_input_checked_by_the_wrapper" {
  command = plan

  variables {
    records = { "bücher" = { A = [{ content = "192.0.2.1", proxid = true }] } }
  }

  expect_failures = [var.records]
}

run "empty_zone_name" {
  command = plan

  variables {
    zone_name = " "
  }

  expect_failures = [var.zone_name]
}

# A value computed by another resource must not make the names and keys unknown (try()
# over the records would): the plan fails with "Invalid count argument" or "Invalid
# for_each argument" then
run "computed_values" {
  command = plan

  module {
    source = "./tests/computed"
  }

  assert {
    condition     = toset(output.keys) == toset(["xn--bcher-kva A 192.0.2.1", "xn--lden-loa A 192.0.2.2"])
    error_message = "Converted names and keys must be known at plan when a value is known only after apply"
  }
}

run "computed_zone_id" {
  command = plan

  module {
    source = "./tests/computed_zone"
  }

  assert {
    condition     = output.keys == ["xn--bcher-kva A 192.0.2.1"]
    error_message = "With a zone ID known only after apply and no zone_name, the plan must not fail on the zone lookup"
  }

  assert {
    condition     = output.keys_named == ["xn--bcher-kva A 192.0.2.1"]
    error_message = "A zone_name known only after apply must not make the keys unknown"
  }
}

# records: [] or record_groups: [] in YAML is a list: it must stop the plan, not pass
# the validations as no records and delete them
run "empty_containers" {
  command = plan

  variables {
    records = { "bücher" = [], "größe" = { A = {} }, "www" = { A = [{ content = "192.0.2.1" }] } }
  }

  assert {
    condition     = keys(module.v5.records) == ["www A 192.0.2.1"]
    error_message = "Empty containers of either kind must be names and types without records"
  }
}

run "list_records" {
  command = plan

  variables {
    records = []
  }

  expect_failures = [var.records]
}

run "list_record_groups" {
  command = plan

  variables {
    record_groups = []
  }

  expect_failures = [var.record_groups]
}

run "require_keys_passed_to_the_wrapper" {
  command = plan

  variables {
    require_keys = ["A"]
    records      = { "straße" = { A = [{ content = "192.0.2.9", key = "web" }] } }
  }

  assert {
    condition     = toset(keys(output.records)) == toset(["xn--strae-oqa A web"])
    error_message = "Records with a key are planned with require_keys"
  }
}

run "require_keys_in_the_wrapper" {
  command = plan

  variables {
    require_keys = ["ALIASES"]
  }

  expect_failures = [var.require_keys]
}
