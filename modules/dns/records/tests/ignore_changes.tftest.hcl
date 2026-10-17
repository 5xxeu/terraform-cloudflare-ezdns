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

run "neighbour_of_the_same_type_fails" {
  command = plan

  # Another configured TXT on the name: if its value changed to the live value of the
  # record with ignore_changes, the match would jump to the other record
  variables {
    records = {
      "_acme-challenge" = {
        TXT = [{ content = "init", key = "acme", ignore_changes = ["content"] }, { content = "static" }]
      }
    }
    existing_records = []
  }

  expect_failures = [output.live_records]
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

run "neighbour_mx_of_another_priority_fails" {
  command = plan

  variables {
    records = {
      "@" = {
        MX = [
          { key = "dynamic", content = "old.example.com", priority = 10, ignore_changes = ["content"] },
          { key = "fixed", content = "mx.example.com", priority = 20 },
        ]
      }
    }
    existing_records = []
  }

  expect_failures = [output.live_records]
}

run "priority_change_keeps_the_record" {
  command = plan

  # The priority is managed: changing it keeps the record found, and its content
  # stays the one in the zone
  variables {
    import_existing = true
    records = {
      "@" = { MX = [{ key = "dynamic", content = "mx.example.com", priority = 20, ignore_changes = ["content"] }] }
    }
    existing_records = [{ id = "id-10", name = "example.com", type = "MX", content = "new.example.com", priority = 10 }]
  }

  assert {
    condition     = output.live_records["@ MX dynamic"].id == "id-10" && output.import_record_ids == { "@ MX dynamic" = "id-10" }
    error_message = "The record is found by name and type only"
  }
}
