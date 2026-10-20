# Applied mock state lets plans prove that addresses and IDs survive input changes.
mock_provider "cloudflare" {}

variables {
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    app = { A = [{ content = "192.0.2.1" }, { key = "web", content = "192.0.2.2" }] }
  }
}

run "initial" {
  command = apply
}

run "reordered" {
  command = plan

  variables {
    records = {
      app = { A = [{ key = "web", content = "192.0.2.2" }, { content = "192.0.2.1" }] }
    }
  }

  assert {
    condition     = output.records == run.initial.records
    error_message = "Reordering must keep record addresses, values and IDs"
  }
}

run "records_to_group" {
  command = apply

  variables {
    records = {}
    record_groups = {
      first = { records = { app = { A = [{ content = "192.0.2.1" }, { key = "web", content = "192.0.2.2" }] } } }
    }
  }

  assert {
    condition     = output.records == run.initial.records
    error_message = "Moving records into a group must keep record addresses, values and IDs"
  }
}

run "group_to_group" {
  command = apply

  variables {
    records = {}
    record_groups = {
      second = { records = { app = { A = [{ content = "192.0.2.1" }, { key = "web", content = "192.0.2.2" }] } } }
    }
  }

  assert {
    condition     = output.records == run.initial.records
    error_message = "Moving records between groups must keep record addresses, values and IDs"
  }
}

run "group_to_records" {
  command = apply

  assert {
    condition     = output.records == run.initial.records
    error_message = "Moving records out of a group must keep record addresses, values and IDs"
  }
}

run "keyed_value_changed" {
  command = plan

  variables {
    records = {
      app = { A = [{ content = "192.0.2.1" }, { key = "web", content = "192.0.2.3" }] }
    }
  }

  assert {
    condition     = { for key, r in output.records : key => r.id } == { for key, r in run.initial.records : key => r.id }
    error_message = "A new value under the same key must keep addresses and IDs, without replacement"
  }

  assert {
    condition     = cloudflare_dns_record.record["app A web"].content == "192.0.2.3" && output.records["app A 192.0.2.1"] == run.initial.records["app A 192.0.2.1"]
    error_message = "Only the keyed record's content must change"
  }
}
