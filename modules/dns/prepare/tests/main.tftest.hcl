# The merge of record_groups into records and the checks of the values as given:
# numbers in text values (a warning) and attributes that do not apply to their record
# type (an error of the input that has them). The wrappers run the same module; their
# tests cover the merged records through the records module.

variables {
  records = {
    "@"   = { MX = [{ content = "mx1.example.com", priority = 10 }] }
    "app" = []
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
        "@"   = { A = [{ content = "192.0.2.1" }], CAA = [{ content = "letsencrypt.org", tag = "issue", flags = 0 }] }
        "www" = { A = [{ content = "192.0.2.2", proxied = false }] }
      }
    }
  }
}

run "merge" {
  command = plan

  assert {
    condition     = toset(keys(output.all_records)) == toset(["@", "app", "_dmarc", "www"])
    error_message = "Names of records and of the groups must be merged"
  }

  assert {
    condition     = [for r in output.all_records["@"]["MX"] : r.content] == ["mx1.example.com", "mx2.example.com"]
    error_message = "Lists of the same name and type must be joined, records first"
  }

  assert {
    condition     = output.all_records["app"] == {}
    error_message = "A name without records must stay a name without records"
  }

  assert {
    condition     = output.all_records["@"]["TXT"][0].ttl == 600 && output.all_records["@"]["TXT"][0].comment == "mail" && output.all_records["@"]["TXT"][0].tags == ["team:mail"]
    error_message = "A record's own value must win over the group default"
  }

  assert {
    condition     = output.all_records["@"]["A"][0].proxied == true && output.all_records["@"]["CAA"][0].proxied == null && output.all_records["www"]["A"][0].proxied == false
    error_message = "The proxied default must apply to the types that can be proxied only"
  }

  assert {
    condition     = output.all_records["_dmarc"]["TXT"][0].source == "record_groups[\"mail\"].records[\"_dmarc\"][\"TXT\"][0]" && !contains(keys(output.all_records["@"]["MX"][0]), "source")
    error_message = "Grouped records must get their source, the records of records must not"
  }
}

# The values are passed on as given, not converted to a type
run "values_as_given" {
  command = plan

  variables {
    records       = { "@" = { TXT = [{ content = "0123", key = "n" }] } }
    record_groups = {}
  }

  assert {
    condition     = output.all_records == { "@" = { TXT = [{ content = "0123", key = "n" }] } }
    error_message = "Records without groups must be returned unchanged"
  }
}

run "yaml_numbers_in_text_values" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      "@":
        TXT:
          - content: 0123
            key: "n"
    YAML
    )
    record_groups = {}
  }

  expect_failures = [check.records_text_values_are_strings]
}

run "yaml_numbers_in_alias_names" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      "@":
        ALIASES:
          - name: 1.10
    YAML
    )
    record_groups = {}
  }

  expect_failures = [check.records_text_values_are_strings]
}

run "yaml_numbers_in_alias_names_of_groups" {
  command = plan

  variables {
    records = {}
    record_groups = yamldecode(<<-YAML
      web:
        records:
          "@":
            ALIASES:
              - name: 0123
    YAML
    )
  }

  expect_failures = [check.records_text_values_are_strings]
}

run "yaml_numbers_in_data_text_fields" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      "@":
        DS:
          - data: { key_tag: 2371, algorithm: 13, digest_type: 2, digest: 0123 }
    YAML
    )
    record_groups = {}
  }

  expect_failures = [check.records_text_values_are_strings]
}

run "yaml_numbers_in_tags" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      app:
        A:
          - content: 192.0.2.1
            tags: [0123]
    YAML
    )
    record_groups = {}
  }

  expect_failures = [check.records_text_values_are_strings]
}

# tags given as a set in HCL: a set has no index, so the values are checked
run "numbers_in_a_set_of_tags" {
  command = plan

  variables {
    records       = { "app" = { A = [{ content = "192.0.2.1", tags = toset([123]) }] } }
    record_groups = {}
  }

  expect_failures = [check.records_text_values_are_strings]
}

run "grouped_record_number_text" {
  command = plan

  variables {
    records       = {}
    record_groups = { web = { records = { "@" = { TXT = [{ content = 123 }] } } } }
  }

  expect_failures = [check.records_text_values_are_strings]
}

# A failed check fails a run that does not expect it: these must plan without the
# warning about numbers. Numeric fields of data may be numbers
run "yaml_numbers_in_numeric_data_fields" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      _sip._tcp:
        SRV:
          - data: { priority: 10, weight: 5, port: 5060, target: sip.example.com }
    YAML
    )
    record_groups = {}
  }

  assert {
    condition     = length(output.all_records["_sip._tcp"]["SRV"]) == 1
    error_message = "SRV with numeric fields"
  }
}

# Attributes set to null, and null fields of data (from an object type with optional(...)
# attributes), are not text given as numbers
run "null_attributes_are_not_numbers" {
  command = plan

  variables {
    records = {
      "app" = { TXT = [{ content = "text", comment = null, key = null }] }
      "@"   = { HTTPS = [{ data = { priority = 1, target = ".", value = "alpn=h2", ipv4hint = null } }] }
    }
    record_groups = {}
  }

  assert {
    condition     = length(output.all_records) == 2
    error_message = "Attributes set to null must not be reported as numbers"
  }
}

# Attributes that do not apply to the type of their record fail the input that has them
run "unused_attributes_in_records" {
  command = plan

  variables {
    records = {
      "_sip._tcp" = { SRV = [{ content = "ignored", data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } }] }
      "app"       = { A = [{ content = "192.0.2.3", priority = 10 }] }
      "@"         = { "_acme-challenge.TXT" = [{ content = "token", flags = 0 }] }
    }
    record_groups = {}
  }

  expect_failures = [var.records]
}

run "unused_attributes_in_record_groups" {
  command = plan

  variables {
    records       = {}
    record_groups = { web = { records = { "@" = { TXT = [{ content = "v=spf1 -all", tag = "issue" }] } } } }
  }

  expect_failures = [var.record_groups]
}

# ALIASES name the CNAME in name: content (the syntax of 2.x) fails, and so does name
# on any other type
run "aliases_content_in_records" {
  command = plan

  variables {
    records       = { "app" = { ALIASES = [{ content = "www" }] } }
    record_groups = {}
  }

  expect_failures = [var.records]
}

run "aliases_content_in_record_groups" {
  command = plan

  variables {
    records       = {}
    record_groups = { web = { records = { "app" = { "cdn.ALIASES" = [{ content = "static" }] } } } }
  }

  expect_failures = [var.record_groups]
}

run "name_on_other_types" {
  command = plan

  variables {
    records       = { "app" = { A = [{ content = "192.0.2.1", name = "www" }] } }
    record_groups = {}
  }

  expect_failures = [var.records]
}

# Each attribute where it applies, and attributes set to null anywhere: no error. Types
# that the module does not know are left to the records module
run "attributes_where_they_apply" {
  command = plan

  variables {
    records = {
      "@" = {
        MX  = [{ content = "mx.example.com", priority = 10 }]
        CAA = [{ content = "letsencrypt.org", tag = "issue", flags = 0 }]
        SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }, content = null, priority = null }]
        URI = [{ priority = 10, data = { weight = 1, target = "https://example.com" } }]
        A   = [{ content = "192.0.2.1", tag = null, flags = null }]
        SPF = [{ content = "v=spf1 -all", priority = 10 }]
      }
      "www" = { ALIASES = [{ name = "w1" }] }
    }
    record_groups = { web = { records = { "@" = { CAA = [{ content = "pki.goog", tag = "issue" }] } } } }
  }

  assert {
    condition     = length(output.all_records["@"]) == 6
    error_message = "Attributes where they apply must not fail"
  }
}

# Malformed inputs are reported by the calling module, which checks their shapes: the
# checks of attributes here must not add errors of their own
run "malformed_inputs" {
  command = plan

  variables {
    records       = { "app" = { A = { content = "192.0.2.1", priority = 10 }, MX = ["x"] } }
    record_groups = { web = { records = [] }, db = "x", app = { records = { "@" = [] } } }
  }

  assert {
    condition     = contains(keys(output.all_records), "app")
    error_message = "Malformed inputs must plan"
  }
}

# null is {}: the calling module rejects null itself
run "null_inputs" {
  command = plan

  variables {
    records       = null
    record_groups = null
  }

  assert {
    condition     = output.all_records == {}
    error_message = "null inputs must be no records"
  }
}

# A value known only after apply keeps the names and types known, and the check of an
# attribute with such a value is put off until apply (the plan does not fail)
run "computed_values" {
  command = plan

  module {
    source = "./tests/computed"
  }

  assert {
    condition     = output.names == { "@" = "A TXT", "app" = "A", "www" = "A" }
    error_message = "Names and types must be known at plan when a value is known only after apply"
  }
}
