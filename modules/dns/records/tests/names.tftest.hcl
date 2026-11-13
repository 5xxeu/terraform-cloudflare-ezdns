# Invariants of name normalization: every way to write a name gives one fully
# qualified name, qualifying a qualified name changes nothing, and different
# records never share a key

variables {
  root_domain = "example.com"
  # One A record per form, with different addresses, so none of them is a duplicate
  records = {
    "@"                    = { A = [{ content = "192.0.2.1" }], "_dmarc.A" = [{ content = "192.0.2.20" }] }
    "example.com"          = { A = [{ content = "192.0.2.2" }] }
    "EXAMPLE.Com"          = { A = [{ content = "192.0.2.3" }] }
    "www"                  = { A = [{ content = "192.0.2.4" }] }
    "www.example.com"      = { A = [{ content = "192.0.2.5" }] }
    "WWW.Example.COM"      = { A = [{ content = "192.0.2.6" }] }
    "*"                    = { A = [{ content = "192.0.2.7" }] }
    "*.app.example.com"    = { A = [{ content = "192.0.2.8" }] }
    "app"                  = { "_acme-challenge.A" = [{ content = "192.0.2.9" }], "x.y.A" = [{ content = "192.0.2.10" }] }
    "App.example.com"      = { "_acme-challenge.A" = [{ content = "192.0.2.11" }] }
    "notexample.com"       = { A = [{ content = "192.0.2.12" }] }
    "example.com.example"  = { A = [{ content = "192.0.2.13" }] }
    "sub.example.com.test" = { A = [{ content = "192.0.2.14" }] }
  }
}

run "forms" {
  command = plan

  assert {
    condition = { for k, r in output.flat_records : r.content => r.fqdn } == {
      "192.0.2.1"  = "example.com"
      "192.0.2.20" = "_dmarc.example.com"
      "192.0.2.2"  = "example.com"
      "192.0.2.3"  = "example.com"
      "192.0.2.4"  = "www.example.com"
      "192.0.2.5"  = "www.example.com"
      "192.0.2.6"  = "www.example.com"
      "192.0.2.7"  = "*.example.com"
      "192.0.2.8"  = "*.app.example.com"
      "192.0.2.9"  = "_acme-challenge.app.example.com"
      "192.0.2.10" = "x.y.app.example.com"
      "192.0.2.11" = "_acme-challenge.app.example.com"
      # The zone name is a suffix only at a label boundary
      "192.0.2.12" = "notexample.com.example.com"
      "192.0.2.13" = "example.com.example.example.com"
      "192.0.2.14" = "sub.example.com.test.example.com"
    }
    error_message = "Short, fully qualified and differently cased names must give one fully qualified name"
  }

  assert {
    condition     = alltrue([for k, r in output.flat_records : r.fqdn == lower(r.fqdn) && !endswith(r.fqdn, ".") && r.name == lower(r.name)])
    error_message = "Fully qualified names and record names are lower case, without a trailing dot"
  }

  assert {
    condition     = length(output.flat_records) == 15 && length(distinct([for k, r in output.flat_records : lower(k)])) == 15
    error_message = "Every record gets its own key, also when keys are compared case-insensitively"
  }
}

# The fully qualified names of the first run as base names give the same names
run "qualified_is_idempotent" {
  command = plan

  variables {
    records = {
      for fqdn in distinct([for k, r in run.forms.flat_records : r.fqdn]) : fqdn => {
        A = [for k, r in run.forms.flat_records : { content = r.content } if r.fqdn == fqdn]
      }
    }
  }

  assert {
    condition     = { for k, r in output.flat_records : r.content => r.fqdn } == { for k, r in run.forms.flat_records : r.content => r.fqdn }
    error_message = "Qualifying a fully qualified name must not change it"
  }

  assert {
    condition     = alltrue([for k, r in output.flat_records : r.fqdn == r.name])
    error_message = "A fully qualified name is kept as the record name"
  }
}

# The case of the zone name does not change the names
run "zone_name_case" {
  command = plan

  variables {
    root_domain = "Example.COM"
  }

  assert {
    condition     = { for k, r in output.flat_records : r.content => r.fqdn } == { for k, r in run.forms.flat_records : r.content => r.fqdn }
    error_message = "The zone name is compared case-insensitively"
  }
}

# One record written in two forms of the same name is a duplicate, whatever the forms
run "same_record_apex_and_zone_name_case" {
  command = plan

  variables {
    records = {
      "@"           = { TXT = [{ content = "v=spf1 -all" }] }
      "EXAMPLE.com" = { TXT = [{ content = "v=spf1 -all" }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"example.com TXT 18de4b91f5e3\" as \"@ TXT d2b1e35921ca\" from records[\"@\"][\"TXT\"][0] and \"EXAMPLE.com TXT d2b1e35921ca\" from records[\"EXAMPLE.com\"][\"TXT\"][0]"]
    error_message = "The records are reported as duplicates"
  }
}

run "same_record_prefix_and_base_name" {
  command = plan

  variables {
    records = {
      "app"                             = { "_acme-challenge.TXT" = [{ content = "token" }] }
      "_acme-challenge.APP.example.com" = { TXT = [{ content = "token" }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"_acme-challenge.app.example.com TXT 7deab982ae4b\" as \"_acme-challenge.APP.example.com TXT ee977806d728\" from records[\"_acme-challenge.APP.example.com\"][\"TXT\"][0] and \"_acme-challenge.app TXT ee977806d728\" from records[\"app\"][\"_acme-challenge.TXT\"][0]"]
    error_message = "The records are reported as duplicates"
  }
}

run "same_record_prefix_under_apex" {
  command = plan

  variables {
    records = {
      "@"                  = { "_dmarc.TXT" = [{ content = "v=DMARC1; p=none" }] }
      "_dmarc.example.com" = { TXT = [{ content = "v=DMARC1; p=none" }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"_dmarc.example.com TXT fad06b433893\" as \"_dmarc TXT 21541c4e7044\" from records[\"@\"][\"_dmarc.TXT\"][0] and \"_dmarc.example.com TXT 21541c4e7044\" from records[\"_dmarc.example.com\"][\"TXT\"][0]"]
    error_message = "The records are reported as duplicates"
  }
}

run "same_alias_name_forms" {
  command = plan

  variables {
    records = {
      "@"               = { ALIASES = [{ name = "www" }] }
      "WWW.example.com" = { CNAME = [{ content = "example.com." }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"www.example.com CNAME example.com\" as \"www CNAME\" from records[\"@\"][\"ALIASES\"][0] and \"WWW.example.com CNAME\" from records[\"WWW.example.com\"][\"CNAME\"][0]"]
    error_message = "The records are reported as duplicates"
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"www.example.com\": CNAME from records[\"@\"][\"ALIASES\"][0], CNAME from records[\"WWW.example.com\"][\"CNAME\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

# A wildcard is only valid as the whole leftmost label

run "wildcard_as_the_last_label" {
  command = plan

  variables {
    records = { "foo.*" = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "wildcard_inside_a_label" {
  command = plan

  variables {
    records = { "*foo" = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "wildcard_inside_a_word" {
  command = plan

  variables {
    records = { "foo*bar.example.com" = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "wildcard_in_the_middle" {
  command = plan

  variables {
    records = { "foo.*.app" = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "wildcard_forms" {
  command = plan

  variables {
    records = {
      "*"                 = { A = [{ content = "192.0.2.1" }] }
      "*.app"             = { A = [{ content = "192.0.2.2" }] }
      "*.EXAMPLE.COM"     = { TXT = [{ content = "wildcard at the apex" }] }
      "*.App.Example.com" = { TXT = [{ content = "wildcard under app" }] }
    }
  }

  assert {
    condition     = sort([for k, r in output.flat_records : r.fqdn]) == tolist(["*.app.example.com", "*.app.example.com", "*.example.com", "*.example.com"])
    error_message = "A wildcard name is qualified and lower-cased like any other name"
  }
}

# Names are written without a trailing dot; only values (CNAME, MX, NS, PTR targets) may have one

run "base_name_with_a_trailing_dot" {
  command = plan

  variables {
    records = { "www." = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "zone_name_with_a_trailing_dot" {
  command = plan

  variables {
    records = { "example.com." = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

# Internationalized names are given in Punycode, as the Cloudflare API expects them
run "punycode" {
  command = plan

  variables {
    records = {
      "xn--mnchen-3ya" = { A = [{ content = "192.0.2.1" }], MX = [{ content = "mail.xn--mnchen-3ya.example.", priority = 10 }] }
      "shop"           = { CNAME = [{ content = "xn--bcher-kva.example" }] }
    }
  }

  assert {
    condition     = output.flat_records["xn--mnchen-3ya A 192.0.2.1"].fqdn == "xn--mnchen-3ya.example.com" && output.flat_records["shop CNAME"].content == "xn--bcher-kva.example"
    error_message = "Punycode names and targets are accepted as they are"
  }
}

run "unicode_name" {
  command = plan

  variables {
    records = { "münchen" = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "unicode_target" {
  command = plan

  variables {
    records = { "shop" = { CNAME = [{ content = "bücher.example" }] } }
  }

  expect_failures = [var.records]
}

# The zone name may be given with a trailing dot, as in zone files: same names
run "root_domain_with_a_trailing_dot" {
  command = plan

  variables {
    root_domain = "example.com."
  }

  assert {
    condition     = { for k, r in output.flat_records : r.content => r.fqdn } == { for k, r in run.forms.flat_records : r.content => r.fqdn }
    error_message = "A trailing dot of the zone name must not change any name"
  }
}

run "aliases_with_root_domain_with_a_trailing_dot" {
  command = plan

  variables {
    root_domain = "example.com."
    records     = { "@" = { ALIASES = [{ name = "www" }] }, "app" = { "cdn.ALIASES" = [{ name = "static" }] } }
  }

  assert {
    condition     = output.flat_records["www CNAME"].content == "example.com" && output.flat_records["static CNAME"].content == "cdn.app.example.com"
    error_message = "Alias targets have no trailing dot from the zone name"
  }
}

run "invalid_root_domain" {
  command = plan

  variables {
    root_domain = "example com"
  }

  expect_failures = [var.root_domain]
}

run "empty_root_domain" {
  command = plan

  variables {
    root_domain = ""
  }

  expect_failures = [var.root_domain]
}

# Cloudflare returns the name of an internationalized zone in Unicode
run "unicode_root_domain" {
  command = plan

  variables {
    root_domain = "münchen.de"
  }

  expect_failures = [var.root_domain]
}

run "punycode_root_domain" {
  command = plan

  variables {
    root_domain = "xn--mnchen-3ya.de"
    records     = { "www" = { A = [{ content = "192.0.2.1" }] } }
  }

  assert {
    condition     = output.flat_records["www A 192.0.2.1"].fqdn == "www.xn--mnchen-3ya.de"
    error_message = "A zone name in Punycode gives fully qualified names in Punycode"
  }
}
