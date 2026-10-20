# require_keys: records of the listed types must have a key, so a new value is an
# update in place; records of other types and CNAME records are not affected

variables {
  root_domain = "example.com"
  records = {
    "app" = {
      A                     = [{ content = "192.0.2.1", key = "web" }]
      TXT                   = [{ content = "v=spf1 -all" }]
      "_acme-challenge.TXT" = [{ content = "token", key = "acme" }]
      ALIASES               = [{ content = "www" }]
    }
  }
}

run "not_required_by_default" {
  command = plan

  assert {
    condition     = length(output.flat_records) == 4
    error_message = "Records without a key are accepted when require_keys is empty"
  }
}

run "records_with_keys" {
  command = plan

  variables {
    require_keys = ["A", "MX"]
  }

  assert {
    condition     = contains(keys(output.flat_records), "app A web") && contains(keys(output.flat_records), "www CNAME")
    error_message = "Records with a key and records of other types are accepted"
  }
}

run "record_without_a_key" {
  command = plan

  variables {
    require_keys = ["TXT"]
  }

  expect_failures = [output.flat_records]
}

run "grouped_record_without_a_key" {
  command = plan

  variables {
    require_keys = ["A"]
    records = {
      "app" = { A = [{ content = "192.0.2.1", source = "record_groups[\"web\"]" }] }
    }
  }

  expect_failures = [output.flat_records]
}

run "cname_cannot_be_listed" {
  command = plan

  variables {
    require_keys = ["CNAME"]
  }

  expect_failures = [var.require_keys]
}

run "types_in_upper_case" {
  command = plan

  variables {
    require_keys = ["txt"]
  }

  expect_failures = [var.require_keys]
}
