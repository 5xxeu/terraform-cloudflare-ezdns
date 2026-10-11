# The compile module runs the checks of the wrappers (the same code, see
# scripts/check-sync.sh) and returns the records without a provider.

variables {
  zone_name = "example.com"
  records = {
    "@"    = { MX = [{ content = "mx.example.com", priority = 10 }], A = [{ content = "192.0.2.1", proxied = true }] }
    "mail" = { A = [{ content = "192.0.2.2" }] }
  }
  record_groups = {
    web = { defaults = { ttl = 300 }, records = { "www" = { CNAME = [{ content = "@" }] } } }
  }
}

run "records" {
  command = plan

  assert {
    condition     = toset(keys(output.records)) == toset(["@ MX mx.example.com", "@ A 192.0.2.1", "mail A 192.0.2.2", "www CNAME"])
    error_message = "Records and grouped records must be returned by their keys"
  }

  assert {
    condition     = output.records["www CNAME"].ttl == 300 && output.records["www CNAME"].fqdn == "www.example.com"
    error_message = "Group defaults and fully qualified names must be applied"
  }

  assert {
    condition     = output.records["@ A 192.0.2.1"].ttl == 1 && output.records["mail A 192.0.2.2"].ttl == 3600
    error_message = "Proxied records get TTL 1, like in the wrappers"
  }

  # The kind of assertion a user's test can make about a zone
  assert {
    condition     = length([for r in output.records : r if r.type == "MX"]) > 0 && !anytrue([for r in output.records : r.proxied if r.fqdn == "mail.example.com"])
    error_message = "The zone must keep its MX records, and the mail host must not be proxied"
  }
}

run "unknown_attribute" {
  command = plan

  variables {
    records = { "@" = { A = [{ content = "192.0.2.1", proxid = true }] } }
  }

  expect_failures = [var.records]
}

run "boolean_text" {
  command = plan

  variables {
    records = { "@" = { TXT = [{ content = false }] } }
  }

  expect_failures = [var.records]
}

run "unused_attribute" {
  command = plan

  variables {
    records = { "@" = { A = [{ content = "192.0.2.1", priority = 10 }] } }
  }

  expect_failures = [check.records_unused_attributes]
}

run "zone_name_required_in_punycode" {
  command = plan

  variables {
    zone_name = "münchen.de"
  }

  expect_failures = [var.zone_name]
}
