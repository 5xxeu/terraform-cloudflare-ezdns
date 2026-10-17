# Records with ignore_changes: the record in the zone is found by name and type

variables {
  root_domain = "example.com"
  records = {
    "_acme-challenge" = {
      TXT = [{ content = "init", key = "acme", ignore_changes = ["content"] }]
    }
    "@" = {
      TXT = [{ content = "v=spf1 -all" }]
    }
    "dyn" = {
      A = [{ content = "192.0.2.1", key = "home", ignore_changes = ["content", "ttl"] }]
    }
  }
  existing_records = [
    { id = "id-acme", name = "_acme-challenge.example.com", type = "TXT", content = "token-from-cert-manager", ttl = 120 },
    { id = "id-spf", name = "example.com", type = "TXT", content = "v=spf1 -all" },
    { id = "id-dyn", name = "dyn.example.com", type = "A", content = "198.51.100.7", ttl = 60 },
    { id = "id-other", name = "other.example.com", type = "A", content = "192.0.2.9" },
  ]
  report_unmanaged = true
}

run "live_record_by_name_and_type" {
  command = plan

  assert {
    condition     = output.live_records["_acme-challenge TXT acme"].id == "id-acme" && output.live_records["_acme-challenge TXT acme"].content == "token-from-cert-manager"
    error_message = "The record with ignore_changes is found by name and type, whatever its value"
  }

  assert {
    condition     = output.live_records["dyn A home"].content == "198.51.100.7" && output.live_records["dyn A home"].ttl == 60
    error_message = "The live record carries content and ttl"
  }

  assert {
    condition     = !contains(keys(output.live_records), "@ TXT v=spf1 -all")
    error_message = "Records without ignore_changes have no live record"
  }

  assert {
    condition     = [for r in output.unmanaged_records : r.id] == ["id-other"]
    error_message = "The live records of ignore_changes are managed, not reported"
  }
}

run "record_not_created_yet" {
  command = plan

  variables {
    existing_records = []
  }

  assert {
    condition     = output.live_records["_acme-challenge TXT acme"] == null
    error_message = "Without a record in the zone, the configured values are used"
  }
}

run "records_described_by_value_are_left_out" {
  command = plan

  # A second TXT on the name that another configured record describes by value
  variables {
    records = {
      "_acme-challenge" = {
        TXT = [{ content = "init", key = "acme", ignore_changes = ["content"] }, { content = "static" }]
      }
    }
    existing_records = [
      { id = "id-acme", name = "_acme-challenge.example.com", type = "TXT", content = "token" },
      { id = "id-static", name = "_acme-challenge.example.com", type = "TXT", content = "static" },
    ]
  }

  assert {
    condition     = output.live_records["_acme-challenge TXT acme"].id == "id-acme"
    error_message = "A record that another configured record describes is not the live record"
  }
}

run "several_live_candidates_fail" {
  command = plan

  variables {
    existing_records = [
      { id = "id-1", name = "_acme-challenge.example.com", type = "TXT", content = "a" },
      { id = "id-2", name = "_acme-challenge.example.com", type = "TXT", content = "b" },
    ]
  }

  expect_failures = [output.live_records]
}

run "two_ignored_records_on_one_name_fail" {
  command = plan

  variables {
    records = {
      "_acme-challenge" = {
        TXT = [{ content = "a", key = "one", ignore_changes = ["content"] }, { content = "b", key = "two", ignore_changes = ["content"] }]
      }
    }
    existing_records = []
  }

  expect_failures = [output.live_records]
}

run "unknown_attribute_fails" {
  command = plan

  variables {
    records = {
      "x" = { TXT = [{ content = "a", ignore_changes = ["name"] }] }
    }
    existing_records = []
  }

  expect_failures = [output.live_records]
}

run "import_of_the_live_record" {
  command = plan

  variables {
    import_existing = true
  }

  assert {
    condition     = output.import_record_ids["_acme-challenge TXT acme"] == "id-acme" && output.import_record_ids["dyn A home"] == "id-dyn"
    error_message = "import_existing imports the live record of a record with ignore_changes"
  }
}

run "one_id_one_address" {
  command = plan

  # The only MX of the zone (priority 10) is the live record of "dynamic"; "fixed"
  # (priority 20, the same content) must not import it too
  variables {
    import_existing = true
    records = {
      "@" = {
        MX = [
          { key = "dynamic", content = "old.example.com", priority = 10, ignore_changes = ["content"] },
          { key = "fixed", content = "mx.example.com", priority = 20 },
        ]
      }
    }
    existing_records = [{ id = "same-id", name = "example.com", type = "MX", content = "mx.example.com", priority = 10 }]
  }

  assert {
    condition     = output.import_record_ids == { "@ MX dynamic" = "same-id" } && length(output.import_duplicates) == 0
    error_message = "An existing record is imported into one address only"
  }
}

run "ignored_record_not_matched_by_its_configured_value" {
  command = plan

  # "dynamic" was changed in the zone; two other MX with its configured content are
  # described by the configuration, so nothing is ambiguous
  variables {
    import_existing = true
    records = {
      "@" = {
        MX = [
          { key = "dynamic", content = "mx.example.com", priority = 10, ignore_changes = ["content"] },
          { key = "b", content = "mx.example.com", priority = 20 },
          { key = "c", content = "mx.example.com", priority = 30 },
        ]
      }
    }
    existing_records = [
      { id = "id-10", name = "example.com", type = "MX", content = "new.example.com", priority = 10 },
      { id = "id-20", name = "example.com", type = "MX", content = "mx.example.com", priority = 20 },
      { id = "id-30", name = "example.com", type = "MX", content = "mx.example.com", priority = 30 },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "@ MX dynamic" = "id-10", "@ MX b" = "id-20", "@ MX c" = "id-30" } && length(output.import_duplicates) == 0
    error_message = "A record with ignore_changes takes the live record of its priority, the others theirs"
  }
}
