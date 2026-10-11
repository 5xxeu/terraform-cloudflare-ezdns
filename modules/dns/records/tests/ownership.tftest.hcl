# owned_names (the part of the zone a module call manages) and unmanaged_ignore (records
# left out of the report of unmanaged records).

variables {
  root_domain     = "example.com"
  import_existing = false
  records = {
    "apps"     = { A = [{ content = "192.0.2.1" }] }
    "web.apps" = { A = [{ content = "192.0.2.2" }] }
  }
  existing_records = [
    { id = "id-apps", name = "apps.example.com", type = "A", content = "192.0.2.1" },
    { id = "id-stray", name = "old.apps.example.com", type = "A", content = "192.0.2.9" },
    { id = "id-k8s", name = "svc.k8s.apps.example.com", type = "A", content = "192.0.2.10" },
    { id = "id-k8s-txt", name = "extdns-svc.k8s.apps.example.com", type = "TXT", content = "heritage=external-dns" },
    { id = "id-myapps", name = "myapps.example.com", type = "A", content = "192.0.2.11" },
    { id = "id-mx", name = "example.com", type = "MX", content = "mx.example.net", priority = 10 },
    { id = "id-ownership", name = "a-web.apps.example.com", type = "TXT", content = "heritage=external-dns" },
  ]
}

run "whole_zone_by_default" {
  command = plan

  assert {
    condition     = toset([for r in output.unmanaged_records : r.id]) == toset(["id-stray", "id-k8s", "id-k8s-txt", "id-myapps", "id-mx", "id-ownership"])
    error_message = "Without owned_names, every unmatched record of the zone is reported"
  }
}

run "owned_subtree" {
  command = plan

  variables {
    owned_names = { include = ["apps"], exclude = ["k8s.apps"] }
  }

  assert {
    condition     = toset([for r in output.unmanaged_records : r.id]) == toset(["id-stray", "id-ownership"])
    error_message = "Only records in included names and below them, outside excluded names, are reported; myapps is not below apps"
  }
}

run "owned_names_fully_qualified_and_case_insensitive" {
  command = plan

  variables {
    owned_names = { include = ["Apps.Example.com."], exclude = ["k8s.apps.example.com"] }
  }

  assert {
    condition     = toset([for r in output.unmanaged_records : r.id]) == toset(["id-stray", "id-ownership"])
    error_message = "owned_names are compared fully qualified and case-insensitively"
  }
}

run "record_outside_owned_names" {
  command = plan

  variables {
    owned_names = { include = ["web.apps"] }
  }

  expect_failures = [output.flat_records]
}

run "record_in_excluded_names" {
  command = plan

  variables {
    owned_names = { include = ["@"], exclude = ["web.apps"] }
  }

  expect_failures = [output.flat_records]
}

run "owned_names_without_include" {
  command = plan

  variables {
    owned_names = { include = [] }
  }

  expect_failures = [var.owned_names]
}

run "owned_names_wildcard" {
  command = plan

  variables {
    owned_names = { include = ["*.apps"] }
  }

  expect_failures = [var.owned_names]
}

run "ignore_by_name_and_type" {
  command = plan

  variables {
    unmanaged_ignore = [
      { name_regex = "^a-|^extdns-", types = ["TXT"] },
      { name_regex = "\\.k8s\\.apps\\.example\\.com$" },
      { types = ["MX"] },
    ]
  }

  assert {
    condition     = toset([for r in output.unmanaged_records : r.id]) == toset(["id-stray", "id-myapps"])
    error_message = "Records matching all fields of an unmanaged_ignore entry must be left out"
  }
}

run "ignore_needs_both_fields_to_match" {
  command = plan

  variables {
    unmanaged_ignore = [{ name_regex = "^myapps\\.", types = ["TXT"] }]
  }

  assert {
    condition     = contains([for r in output.unmanaged_records : r.id], "id-myapps")
    error_message = "An A record must not be left out by an entry for TXT records"
  }
}

run "ignore_entry_without_fields" {
  command = plan

  variables {
    unmanaged_ignore = [{}]
  }

  expect_failures = [var.unmanaged_ignore]
}

run "ignore_invalid_regex" {
  command = plan

  variables {
    unmanaged_ignore = [{ name_regex = "(" }]
  }

  expect_failures = [var.unmanaged_ignore]
}

run "ignore_unknown_type" {
  command = plan

  variables {
    unmanaged_ignore = [{ types = ["ALIASES"] }]
  }

  expect_failures = [var.unmanaged_ignore]
}
