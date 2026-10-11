# record_groups: merging with records, group defaults and their precedence, and the
# checks of grouped records. Duplicates across groups are checked by the core
# (modules/dns/records/tests/main.tftest.hcl, source of grouped records).

mock_provider "cloudflare" {}

variables {
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    "@" = { MX = [{ content = "mx1.example.com", priority = 10 }] }
  }
  record_groups = {
    mail = {
      defaults = { ttl = 300, comment = "mail", tags = ["team:mail"] }
      records = {
        "@"      = { MX = [{ content = "mx2.example.com", priority = 20 }], TXT = [{ content = "v=spf1 mx -all", ttl = 600 }] }
        "_dmarc" = { TXT = [{ content = "v=DMARC1; p=reject", comment = "dmarc" }] }
      }
    }
    web = {
      defaults = { proxied = true }
      records = {
        "@"   = { A = [{ content = "192.0.2.1" }], CAA = [{ content = "letsencrypt.org", tag = "issue" }] }
        "app" = { A = [{ content = "192.0.2.2", proxied = false }] }
      }
    }
  }
  default_tags = ["managed-by:terraform"]
}

run "merged" {
  command = plan

  assert {
    condition     = length(cloudflare_dns_record.record) == 7
    error_message = "Records and all groups must be merged"
  }

  assert {
    condition     = cloudflare_dns_record.record["@ MX mx1.example.com"].ttl == 3600 && cloudflare_dns_record.record["@ MX mx2.example.com"].ttl == 300
    error_message = "Records keep the module default, grouped records get the group default"
  }

  assert {
    condition     = cloudflare_dns_record.record["@ TXT ${substr(sha1("v=spf1 mx -all"), 0, 12)}"].ttl == 600
    error_message = "A record's own TTL wins over the group default"
  }

  assert {
    condition     = cloudflare_dns_record.record["_dmarc TXT ${substr(sha1("v=DMARC1; p=reject"), 0, 12)}"].comment == "dmarc" && cloudflare_dns_record.record["@ MX mx2.example.com"].comment == "mail"
    error_message = "A record's own comment wins over the group default"
  }

  assert {
    condition     = toset(cloudflare_dns_record.record["@ MX mx2.example.com"].tags) == toset(["managed-by:terraform", "team:mail"]) && toset(cloudflare_dns_record.record["@ MX mx1.example.com"].tags) == toset(["managed-by:terraform"])
    error_message = "Group tags are added to default_tags"
  }

  assert {
    condition     = cloudflare_dns_record.record["@ A 192.0.2.1"].proxied == true && cloudflare_dns_record.record["app A 192.0.2.2"].proxied == false
    error_message = "The group proxied default applies unless the record sets proxied"
  }

  assert {
    condition     = module.records.flat_records["@ CAA issue letsencrypt.org"].proxied == false
    error_message = "The group proxied default does not apply to types that cannot be proxied"
  }
}

run "groups_only" {
  command = plan

  variables {
    records = {}
  }

  assert {
    condition     = length(cloudflare_dns_record.record) == 6
    error_message = "records may be empty when the records are in groups"
  }
}

run "group_without_defaults" {
  command = plan

  variables {
    record_groups = { web = { records = { "@" = { A = [{ content = "192.0.2.1" }] } } } }
  }

  assert {
    condition     = length(cloudflare_dns_record.record) == 2
    error_message = "A group without defaults uses the module defaults"
  }
}

run "group_unknown_attribute" {
  command = plan

  variables {
    record_groups = { web = { default = { ttl = 300 }, records = {} } }
  }

  expect_failures = [var.record_groups]
}

run "group_without_records" {
  command = plan

  variables {
    record_groups = { web = { defaults = { ttl = 300 } } }
  }

  expect_failures = [var.record_groups]
}

run "group_unknown_default" {
  command = plan

  variables {
    record_groups = { web = { defaults = { proxid = true }, records = {} } }
  }

  expect_failures = [var.record_groups]
}

run "group_default_of_wrong_type" {
  command = plan

  variables {
    record_groups = { web = { defaults = { ttl = "5m" }, records = {} } }
  }

  expect_failures = [var.record_groups]
}

run "grouped_record_unknown_attribute" {
  command = plan

  variables {
    record_groups = { web = { records = { "@" = { A = [{ content = "192.0.2.1", proxid = true }] } } } }
  }

  expect_failures = [var.record_groups]
}

run "grouped_record_boolean_text" {
  command = plan

  variables {
    record_groups = { web = { records = { "@" = { TXT = [{ content = false }] } } } }
  }

  expect_failures = [var.record_groups]
}

run "grouped_record_number_text" {
  command = plan

  variables {
    record_groups = { web = { records = { "@" = { TXT = [{ content = 123 }] } } } }
  }

  expect_failures = [check.records_text_values_are_strings]
}

run "unused_attributes" {
  command = plan

  variables {
    records = {
      "_sip._tcp" = { SRV = [{ content = "ignored", data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } }] }
      "app"       = { A = [{ content = "192.0.2.3", priority = 10 }] }
    }
    record_groups = { web = { records = { "@" = { TXT = [{ content = "v=spf1 -all", tag = "issue" }] } } } }
  }

  expect_failures = [check.records_unused_attributes]
}

run "null_attributes_are_not_numbers" {
  command = plan

  variables {
    records       = { "app" = { TXT = [{ content = "text", comment = null, key = null }] } }
    record_groups = {}
  }

  assert {
    condition     = length(cloudflare_dns_record.record) == 1
    error_message = "Attributes set to null must not be reported as numbers"
  }
}

# A value computed by another resource must not make the keys unknown (try() over the
# records would): the plan fails with "Invalid for_each argument" then
run "computed_values" {
  command = plan

  module {
    source = "./tests/computed"
  }

  assert {
    condition     = toset(output.keys) == toset(["@ A 192.0.2.1", "www A 192.0.2.2"])
    error_message = "Record keys must be known at plan when a value is known only after apply"
  }
}

# Records only in groups are imported too: their types are looked up
run "import_lookup_of_grouped_types" {
  command = plan

  variables {
    records         = {}
    import_existing = true
    record_groups = {
      mail = { records = { "@" = { MX = [{ content = "mx.example.com", priority = 10 }] } } }
      web  = { records = { "@" = { ALIASES = [{ content = "www" }] } } }
    }
  }

  assert {
    condition     = toset(keys(data.cloudflare_dns_records.existing)) == toset(["MX", "CNAME"])
    error_message = "The types of grouped records must be looked up for import_existing"
  }
}
