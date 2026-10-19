# The report of unmanaged records with records in it. The mocked provider cannot return
# the nested result list of cloudflare_dns_records, so the core is overridden with a
# report; matching and filtering are tested in modules/dns/records.

mock_provider "cloudflare" {}

override_module {
  target = module.records
  outputs = {
    flat_records              = {}
    state_migration           = {}
    import_record_ids         = {}
    import_duplicates         = {}
    ambiguous_matches         = {}
    presumed_previous_records = [{ id = "id-previous", name = "app.example.com", type = "A" }]
    unmanaged_records         = [{ id = "id-1", name = "old.example.com", type = "A", content = "192.0.2.9", priority = null, data = null }]
  }
}

variables {
  zone_id          = "z"
  zone_name        = "example.com"
  records          = {}
  report_unmanaged = true
}

run "warn_by_default" {
  command = plan

  assert {
    condition     = output.presumed_previous_records == [{ id = "id-previous", name = "app.example.com", type = "A" }]
    error_message = "Presumed previous records are passed through when report_unmanaged is true"
  }

  expect_failures = [check.unmanaged_records]
}

run "error_stops_the_plan" {
  command = plan

  variables {
    unmanaged_policy = "error"
  }

  expect_failures = [output.unmanaged_records]
}

run "no_presumed_previous_records_without_report_unmanaged" {
  command = plan

  variables {
    report_unmanaged = false
  }

  assert {
    condition     = output.presumed_previous_records == []
    error_message = "Presumed previous records are empty unless report_unmanaged is true"
  }
}
