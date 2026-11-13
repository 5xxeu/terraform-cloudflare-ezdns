# Each input fails its validation when its list is not empty. The lists are built and
# tested in modules/dns/records (output.diagnostics); the messages, as a caller sees them,
# are checked through modules/dns/compile by scripts/test-plan-checks.py

variables {
  flat_records = {
    "app A 192.0.2.1" = { name = "app", fqdn = "app.example.com", type = "A", content = "192.0.2.1" }
  }
  duplicates          = []
  same_values         = []
  low_ttls            = []
  missing_keys        = []
  misplaced_wildcards = []
  long_names          = []
  self_cnames         = []
  not_owned           = []
  cname_conflicts     = []
  owned_include       = ["example.com"]
  owned_exclude       = []
  minimum_ttl         = 60
}

run "no_problems" {
  command = plan

  assert {
    condition     = output.flat_records == var.flat_records
    error_message = "flat_records is passed through when every list is empty"
  }
}

run "duplicates" {
  command = plan

  variables {
    duplicates = ["\"app TXT foo\" from records[\"app\"][\"TXT\"][0] and records[\"app\"][\"TXT\"][1]"]
  }

  expect_failures = [var.duplicates]
}

run "same_values" {
  command = plan

  variables {
    same_values = ["TXT app.example.com from records[\"app\"][\"TXT\"][0] and records[\"app\"][\"TXT\"][1]"]
  }

  expect_failures = [var.same_values]
}

run "low_ttls" {
  command = plan

  variables {
    low_ttls = ["\"app A 192.0.2.1\" (ttl 30) from records[\"app\"][\"A\"][0]"]
  }

  expect_failures = [var.low_ttls]
}

run "missing_keys" {
  command = plan

  variables {
    missing_keys = ["A app.example.com from records[\"app\"][\"A\"][0]"]
  }

  expect_failures = [var.missing_keys]
}

run "misplaced_wildcards" {
  command = plan

  variables {
    misplaced_wildcards = ["\"_acme-challenge.*\" from records[\"*\"][\"_acme-challenge.TXT\"][0]"]
  }

  expect_failures = [var.misplaced_wildcards]
}

run "long_names" {
  command = plan

  variables {
    long_names = ["\"www.example.com\" (300 characters) from records[\"www\"][\"A\"][0]"]
  }

  expect_failures = [var.long_names]
}

run "self_cnames" {
  command = plan

  variables {
    self_cnames = ["\"www CNAME\" from records[\"www\"][\"CNAME\"][0]"]
  }

  expect_failures = [var.self_cnames]
}

run "not_owned" {
  command = plan

  variables {
    not_owned = ["\"app.example.com\" (A) from records[\"app\"][\"A\"][0]"]
  }

  expect_failures = [var.not_owned]
}

run "cname_conflicts" {
  command = plan

  variables {
    cname_conflicts = ["\"app.example.com\": CNAME from records[\"app\"][\"CNAME\"][0], A from records[\"app\"][\"A\"][0]"]
  }

  expect_failures = [var.cname_conflicts]
}

run "several_problems_fail_each_check" {
  command = plan

  variables {
    duplicates = ["\"app TXT foo\" from records[\"app\"][\"TXT\"][0] and records[\"app\"][\"TXT\"][1]"]
    low_ttls   = ["\"app A 192.0.2.1\" (ttl 30) from records[\"app\"][\"A\"][0]"]
  }

  expect_failures = [var.duplicates, var.low_ttls]
}

run "message_context_alone_passes" {
  command = plan

  variables {
    owned_include = ["apps.example.com"]
    owned_exclude = ["k8s.apps.example.com"]
    minimum_ttl   = 30
  }

  assert {
    condition     = output.flat_records == var.flat_records
    error_message = "owned_include, owned_exclude and minimum_ttl only go into the messages"
  }
}
