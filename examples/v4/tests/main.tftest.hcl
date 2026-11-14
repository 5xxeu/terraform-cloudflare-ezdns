mock_provider "cloudflare" {}

variables {
  zone_id = "z"
}

run "plan" {
  command = plan

  assert {
    condition     = length(module.dns.record_names) == 14
    error_message = "Unexpected number of records"
  }

  assert {
    condition     = issensitive(output.records)
    error_message = "The records output of the example must be sensitive (content of a proxied record is its origin address)"
  }
}
