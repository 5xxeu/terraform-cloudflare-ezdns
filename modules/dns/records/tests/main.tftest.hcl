variables {
  root_domain = "example.com"
  records = {
    "@" = {
      A              = [{ content = "30.40.50.61", proxied = true }]
      "_dmarc.TXT"   = [{ content = "v=DMARC1" }]
      ALIASES        = [{ name = "www" }]
      "mail.ALIASES" = [{ name = "m2" }]
    }
    "app" = {
      A                       = [{ content = "30.40.50.60" }, { content = "30.40.50.70" }]
      MX                      = [{ content = "mx.example.com", priority = 5 }]
      CAA                     = [{ content = "letsencrypt.org", tag = "issue" }]
      "_acme-challenge.TXT"   = [{ content = "tok" }]
      "cdn.ALIASES"           = [{ name = "static", ttl = 1800 }]
      "google._domainkey.TXT" = [{ content = "v=DKIM1; p=abc", key = "dkim" }]
    }
  }
}

run "flattening" {
  command = plan

  assert {
    condition     = length(output.flat_records) == 11
    error_message = "Unexpected number of records"
  }

  assert {
    condition     = output.flat_records["_dmarc TXT ${substr(sha1("v=DMARC1"), 0, 12)}"].name == "_dmarc"
    error_message = "Nested name in apex"
  }

  assert {
    condition     = output.flat_records["_acme-challenge.app TXT ${substr(sha1("tok"), 0, 12)}"].name == "_acme-challenge.app"
    error_message = "Nested name"
  }

  assert {
    condition     = output.flat_records["www CNAME"].content == "example.com"
    error_message = "Apex alias"
  }

  assert {
    condition     = output.flat_records["m2 CNAME"].content == "mail.example.com"
    error_message = "Apex inline alias"
  }

  assert {
    condition     = output.flat_records["static CNAME"].content == "cdn.app.example.com" && output.flat_records["static CNAME"].ttl == 1800
    error_message = "Inline alias"
  }

  assert {
    condition     = output.flat_records["app A 30.40.50.70"].ttl == 3600 && output.flat_records["app A 30.40.50.70"].proxied == false
    error_message = "Defaults"
  }

  assert {
    condition     = output.flat_records["app MX mx.example.com"].priority == 5
    error_message = "MX"
  }

  assert {
    condition     = output.flat_records["app CAA issue letsencrypt.org"].data.tag == "issue" && output.flat_records["app CAA issue letsencrypt.org"].data.flags == "0" && output.flat_records["app CAA issue letsencrypt.org"].content == null
    error_message = "CAA"
  }

  assert {
    condition     = output.flat_records["google._domainkey.app TXT dkim"].content == "v=DKIM1; p=abc"
    error_message = "Explicit key"
  }
}

run "duplicate_records" {
  command = plan

  variables {
    records = {
      "app" = {
        A       = [{ content = "1.2.3.4" }, { content = "1.2.3.4" }]
        ALIASES = [{ name = "www" }]
      }
      "www" = { CNAME = [{ content = "other.example.com" }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"app A 1.2.3.4\" from records[\"app\"][\"A\"][0] and records[\"app\"][\"A\"][1]", "\"www CNAME\" from records[\"app\"][\"ALIASES\"][0] and records[\"www\"][\"CNAME\"][0]"]
    error_message = "The records are reported as duplicates"
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"www.example.com\": CNAME from records[\"app\"][\"ALIASES\"][0], CNAME from records[\"www\"][\"CNAME\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "invalid_key" {
  command = plan

  variables {
    records = { "app" = { TXT = [{ content = "x", key = "my key" }] } }
  }

  expect_failures = [var.records]
}

run "unsupported_type" {
  command = plan

  variables {
    records = { "app" = { SRV = [{ content = "x" }] } }
  }

  expect_failures = [var.records]
}

run "missing_content" {
  command = plan

  variables {
    records = { "app" = { A = [{ proxied = true }] } }
  }

  expect_failures = [var.records]
}

run "invalid_ttl" {
  command = plan

  variables {
    records = { "app" = { A = [{ content = "1.2.3.4", ttl = 5 }] } }
  }

  expect_failures = [var.records]
}

run "proxied_txt" {
  command = plan

  variables {
    records = { "app" = { TXT = [{ content = "x", proxied = true }] } }
  }

  expect_failures = [var.records]
}

run "mx_without_priority" {
  command = plan

  variables {
    records = { "app" = { MX = [{ content = "mx.example.com" }] } }
  }

  expect_failures = [var.records]
}

run "caa_without_tag" {
  command = plan

  variables {
    records = { "app" = { CAA = [{ content = "letsencrypt.org" }] } }
  }

  expect_failures = [var.records]
}

run "data_types" {
  command = plan

  variables {
    records = {
      "_sip._tcp" = {
        SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } }]
      }
      "@" = {
        HTTPS      = [{ key = "h3", data = { priority = 1, target = ".", value = "alpn=\"h3,h2\"" } }]
        SVCB       = [{ data = { priority = 1, target = "svc.example.com", value = "port=\"8443\"" } }]
        OPENPGPKEY = [{ content = "mQINBGE" }]
      }
      "_ftp._tcp" = {
        URI = [{ priority = 10, data = { weight = 1, target = "ftp://ftp.example.com/" } }]
      }
      "_25._tcp.mail" = {
        TLSA = [{ key = "mx", data = { usage = 3, selector = 1, matching_type = 1, certificate = "abcdef" } }]
      }
      "office" = {
        LOC = [{ key = "hq", data = { lat_degrees = 59, lat_minutes = 26, lat_seconds = 14, lat_direction = "N", long_degrees = 24, long_minutes = 44, long_seconds = 43, long_direction = "E" } }]
      }
    }
  }

  assert {
    condition     = output.flat_records["_sip._tcp SRV ${substr(sha1(jsonencode({ priority = "10", weight = "5", port = "5060", target = "sip.example.com" })), 0, 12)}"].priority == 10
    error_message = "SRV key is a hash of the data, priority comes from the data"
  }

  assert {
    condition     = output.flat_records["@ HTTPS h3"].content == null && output.flat_records["@ HTTPS h3"].data.target == "." && output.flat_records["@ HTTPS h3"].priority == null
    error_message = "HTTPS"
  }

  assert {
    condition     = one([for k, r in output.flat_records : r.data.target if r.type == "SVCB"]) == "svc.example.com."
    error_message = "SVCB targets get a trailing dot, as Cloudflare returns them"
  }

  assert {
    condition     = output.flat_records["@ OPENPGPKEY mQINBGE"].content == "mQINBGE" && output.flat_records["@ OPENPGPKEY mQINBGE"].data == null
    error_message = "OPENPGPKEY uses content"
  }

  assert {
    condition     = one([for k, r in output.flat_records : r.priority if r.type == "URI"]) == 10
    error_message = "URI priority"
  }

  assert {
    condition     = output.flat_records["_25._tcp.mail TLSA mx"].data.usage == "3" && output.flat_records["office LOC hq"].data.lat_direction == "N"
    error_message = "TLSA and LOC data"
  }
}

run "data_on_content_type" {
  command = plan

  variables {
    records = { "app" = { A = [{ content = "1.2.3.4", data = { target = "x" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_without_data" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ content = "sip.example.com" }] } }
  }

  expect_failures = [var.records]
}

run "srv_missing_field" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, target = "sip.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_unknown_field" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com", proto = "_tcp" } }] } }
  }

  expect_failures = [var.records]
}

run "data_hostnames" {
  command = plan

  variables {
    records = {
      "_sip._tcp"  = { SRV = [{ data = { priority = 0, weight = 0, port = 0, target = "." } }, { data = { priority = 10, weight = 5, port = 5060, target = "SIP.example.com." } }] }
      "@"          = { HTTPS = [{ data = { priority = 0, target = "cdn.example.net" } }] }
      "_dns"       = { SVCB = [{ data = { priority = 1, target = "_dns.resolver.example.net." } }] }
      "sip"        = { NAPTR = [{ data = { order = 100, preference = 10, flags = "S", service = "SIP+D2U", replacement = "_sip._udp.example.com." } }] }
      "_ftp._tcp"  = { URI = [{ priority = 10, data = { weight = 1, target = "ftp://ftp.example.com/" } }] }
      "_xmpp._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 5222, target = "xmpp" } }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 7
    error_message = "Hostnames, \".\" and short names are valid targets; URI targets are URIs and not checked as hostnames"
  }
}

run "srv_target_invalid" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip server.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_target_ip" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "192.0.2.10" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_target_null" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = null } }] } }
  }

  expect_failures = [var.records]
}

run "https_target_at" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = "@" } }] } }
  }

  expect_failures = [var.records]
}

run "svcb_target_url" {
  command = plan

  variables {
    records = { "_dns" = { SVCB = [{ data = { priority = 1, target = "https://resolver.example.net/" } }] } }
  }

  expect_failures = [var.records]
}

run "naptr_replacement_wildcard" {
  command = plan

  variables {
    records = { "sip" = { NAPTR = [{ data = { order = 100, preference = 10, replacement = "*.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_target_too_long" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = join(".", [for i in range(5) : "a${join("", [for j in range(60) : "b"])}"]) } }] } }
  }

  expect_failures = [var.records]
}

run "uri_without_priority" {
  command = plan

  variables {
    records = { "_ftp._tcp" = { URI = [{ data = { weight = 1, target = "ftp://ftp.example.com/" } }] } }
  }

  expect_failures = [var.records]
}

run "cname_conflict" {
  command = plan

  variables {
    records = {
      "app" = { A = [{ content = "1.2.3.4" }] }
      "@"   = { ALIASES = [{ name = "App" }] }
    }
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"app.example.com\": CNAME from records[\"@\"][\"ALIASES\"][0], A from records[\"app\"][\"A\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "cname_at_apex_with_other_records" {
  command = plan

  variables {
    records = {
      "@" = {
        CNAME = [{ content = "target.example.net" }]
        TXT   = [{ content = "v=spf1 -all" }]
        MX    = [{ content = "mx.example.com", priority = 1 }]
      }
      # A prefixed name is a different name, not a conflict
      "app" = {
        CNAME    = [{ content = "target.example.net" }]
        "_x.TXT" = [{ content = "y" }]
      }
    }
  }

  assert {
    condition     = length(output.flat_records) == 5
    error_message = "CNAME at the apex must be allowed together with other records"
  }
}

run "invalid_ipv4" {
  command = plan

  variables {
    records = { "app" = { A = [{ content = "192.168.1.300" }] } }
  }

  expect_failures = [var.records]
}

run "ipv6_in_a_record" {
  command = plan

  variables {
    records = { "app" = { A = [{ content = "2001:db8::1" }] } }
  }

  expect_failures = [var.records]
}

run "ipv4_in_aaaa_record" {
  command = plan

  variables {
    records = { "app" = { AAAA = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "ip_in_cname" {
  command = plan

  variables {
    records = { "app" = { CNAME = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "txt_too_long" {
  command = plan

  variables {
    records = { "app" = { TXT = [{ content = format("%02049d", 0) }] } }
  }

  expect_failures = [var.records]
}

run "invalid_base_name" {
  command = plan

  variables {
    records = { "my app" = { A = [{ content = "192.0.2.1" }] } }
  }

  expect_failures = [var.records]
}

run "invalid_prefix" {
  command = plan

  variables {
    records = { "app" = { "bad..prefix.TXT" = [{ content = "x" }] } }
  }

  expect_failures = [var.records]
}

run "invalid_alias" {
  command = plan

  variables {
    records = { "app" = { ALIASES = [{ name = "-bad" }] } }
  }

  expect_failures = [var.records]
}

# An ALIASES record needs its name (content is not read by the core module: the
# wrappers reject it)
run "alias_without_name" {
  command = plan

  variables {
    records = { "app" = { ALIASES = [{ content = "www" }] } }
  }

  expect_failures = [var.records]
}

run "valid_names" {
  command = plan

  variables {
    records = {
      "*"         = { A = [{ content = "192.0.2.1" }] }
      "*.dev"     = { A = [{ content = "192.0.2.2" }] }
      "_sip._tcp" = { SRV = [{ data = { priority = 1, weight = 1, port = 5060, target = "sip.example.com" } }] }
      "app-1"     = { "_acme-challenge.TXT" = [{ content = "x" }], AAAA = [{ content = "2001:db8::1" }] }
      "cdn"       = { CNAME = [{ content = "target.example.net." }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 6
    error_message = "Wildcards, underscores, hyphens and IPv6 must be accepted"
  }
}

run "two_cnames_with_keys" {
  command = plan

  variables {
    records = {
      "app" = {
        CNAME = [
          { content = "a.example.net", key = "a" },
          { content = "b.example.net", key = "b" },
        ]
      }
    }
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"app.example.com\": CNAME from records[\"app\"][\"CNAME\"][0], CNAME from records[\"app\"][\"CNAME\"][1]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "cname_conflict_across_name_forms" {
  command = plan

  variables {
    records = {
      "www"             = { CNAME = [{ content = "target.example.net" }] }
      "www.example.com" = { TXT = [{ content = "v=spf1 -all" }] }
    }
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"www.example.com\": CNAME from records[\"www\"][\"CNAME\"][0], TXT from records[\"www.example.com\"][\"TXT\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "cname_at_apex_with_a" {
  command = plan

  variables {
    records = {
      "@" = {
        CNAME = [{ content = "target.example.net" }]
        A     = [{ content = "192.0.2.1" }]
      }
      "example.com" = { AAAA = [{ content = "2001:db8::1" }] }
    }
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"example.com\": A from records[\"@\"][\"A\"][0], CNAME from records[\"@\"][\"CNAME\"][0], AAAA from records[\"example.com\"][\"AAAA\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "cname_at_apex_with_a_allowed" {
  command = plan

  variables {
    records = {
      "@" = {
        CNAME = [{ content = "target.example.net" }]
        A     = [{ content = "192.0.2.1" }]
      }
    }
    allowed_cname_conflicts = ["@"]
  }

  assert {
    condition     = length(output.flat_records) == 2
    error_message = "allowed_cname_conflicts must let an apex CNAME next to an A record through"
  }
}

run "cname_at_apex_by_zone_name" {
  command = plan

  variables {
    records = {
      "example.com" = {
        CNAME = [{ content = "target.example.net" }]
        TXT   = [{ content = "v=spf1 -all" }]
      }
    }
  }

  assert {
    condition     = length(output.flat_records) == 2
    error_message = "The zone name is the apex, where a CNAME may sit next to other records"
  }
}

run "duplicate_across_name_forms" {
  command = plan

  variables {
    records = {
      "www"             = { A = [{ content = "192.0.2.1" }] }
      "www.example.com" = { A = [{ content = "192.0.2.1" }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"www.example.com A 192.0.2.1\" as \"www A 192.0.2.1\" from records[\"www\"][\"A\"][0] and \"www.example.com A 192.0.2.1\" from records[\"www.example.com\"][\"A\"][0]"]
    error_message = "The records are reported as duplicates"
  }
}

run "duplicate_apex_by_zone_name" {
  command = plan

  variables {
    records = {
      "@"           = { TXT = [{ content = "v=spf1 -all" }] }
      "example.com" = { TXT = [{ content = "v=spf1 -all" }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"example.com TXT 18de4b91f5e3\" as \"@ TXT d2b1e35921ca\" from records[\"@\"][\"TXT\"][0] and \"example.com TXT d2b1e35921ca\" from records[\"example.com\"][\"TXT\"][0]"]
    error_message = "The records are reported as duplicates"
  }
}

run "duplicate_hostname_case_and_dot" {
  command = plan

  variables {
    records = {
      "@"           = { MX = [{ content = "mail.example.com", priority = 10 }] }
      "example.com" = { MX = [{ content = "Mail.Example.com.", priority = 10 }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"example.com MX mail.example.com\" as \"@ MX mail.example.com\" from records[\"@\"][\"MX\"][0] and \"example.com MX mail.example.com\" from records[\"example.com\"][\"MX\"][0]"]
    error_message = "The records are reported as duplicates"
  }
}

# Values that the import takes for one record are duplicates too
run "duplicate_txt_quoted_and_literal" {
  command = plan

  variables {
    records = { "@" = { TXT = [{ content = "v=spf1 -all" }, { content = "\"v=spf1\" \" -all\"" }] } }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"example.com TXT 18de4b91f5e3\" as \"@ TXT d2b1e35921ca\" from records[\"@\"][\"TXT\"][0] and \"@ TXT 8cdc4b6a8b5f\" from records[\"@\"][\"TXT\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}

run "duplicate_caa_issuer_case" {
  command = plan

  variables {
    records = { "@" = { CAA = [{ content = "letsencrypt.org", tag = "issue" }, { content = "LetsEncrypt.org", tag = "issue" }] } }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"example.com CAA e3eed0dc6230\" as \"@ CAA issue letsencrypt.org\" from records[\"@\"][\"CAA\"][0] and \"@ CAA issue LetsEncrypt.org\" from records[\"@\"][\"CAA\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}

run "duplicate_data_hostname_and_numbers" {
  command = plan

  variables {
    records = {
      "_sip._tcp" = {
        SRV = [
          { data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } },
          { data = { priority = "10", weight = "5", port = "5060.0", target = "SIP.example.com." } },
        ]
      }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"_sip._tcp SRV 9c61601f99e8\" from records[\"_sip._tcp\"][\"SRV\"][0] and records[\"_sip._tcp\"][\"SRV\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}

run "duplicate_at_and_zone_name_as_target" {
  command = plan

  variables {
    records = { "@" = { MX = [{ content = "@", priority = 10 }, { content = "example.com", priority = 10 }] } }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"example.com MX example.com\" as \"@ MX @\" from records[\"@\"][\"MX\"][0] and \"@ MX example.com\" from records[\"@\"][\"MX\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}

run "same_data_other_numbers_not_duplicates" {
  command = plan

  variables {
    records = {
      "_sip._tcp" = {
        SRV = [
          { data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } },
          { data = { priority = 10, weight = 5, port = 5061, target = "sip.example.com" } },
        ]
      }
      "@" = { CAA = [{ content = "letsencrypt.org; accounturi=https://acme.example/A", tag = "issue" }, { content = "letsencrypt.org; accounturi=https://acme.example/a", tag = "issue" }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 4
    error_message = "Other numbers and CAA parameters in another case are other records"
  }
}

run "same_name_forms_different_records" {
  command = plan

  variables {
    records = {
      "www"             = { A = [{ content = "192.0.2.1" }, { content = "192.0.2.3", key = "Main" }] }
      "www.example.com" = { A = [{ content = "192.0.2.2" }, { content = "192.0.2.4", key = "main" }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 4
    error_message = "Different values or different explicit keys on one name are not duplicates"
  }
}

run "allowed_cname_conflict_listed" {
  command = plan

  variables {
    records = {
      "community" = {
        CNAME = [{ content = "forum.example.net" }]
        MX    = [{ content = "mx.example.net", priority = 10 }]
      }
      "*.legacy" = {
        CNAME = [{ content = "legacy.example.net" }]
        TXT   = [{ content = "v=spf1 -all" }]
      }
    }
    # Another case and the fully qualified form name the same records
    allowed_cname_conflicts = ["Community", "*.legacy.example.com"]
  }

  assert {
    condition     = length(output.flat_records) == 4
    error_message = "Listed names may have a CNAME next to other records"
  }
}

run "cname_conflict_not_listed" {
  command = plan

  variables {
    records = {
      "community" = {
        CNAME = [{ content = "forum.example.net" }]
        MX    = [{ content = "mx.example.net", priority = 10 }]
      }
      "shop" = {
        CNAME = [{ content = "shop.example.net" }]
        TXT   = [{ content = "v=spf1 -all" }]
      }
    }
    allowed_cname_conflicts = ["community"]
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"shop.example.com\": CNAME from records[\"shop\"][\"CNAME\"][0], TXT from records[\"shop\"][\"TXT\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "cname_conflict_empty_list" {
  command = plan

  variables {
    records = {
      "community" = {
        CNAME = [{ content = "forum.example.net" }]
        MX    = [{ content = "mx.example.net", priority = 10 }]
      }
    }
    allowed_cname_conflicts = []
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"community.example.com\": CNAME from records[\"community\"][\"CNAME\"][0], MX from records[\"community\"][\"MX\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "two_cnames_on_a_listed_name" {
  command = plan

  variables {
    records = {
      "community" = {
        CNAME = [
          { content = "a.example.net", key = "a" },
          { content = "b.example.net", key = "b" },
        ]
        MX = [{ content = "mx.example.net", priority = 10 }]
      }
    }
    allowed_cname_conflicts = ["community"]
  }

  assert {
    condition     = output.diagnostics.cname_conflicts == ["\"community.example.com\": CNAME from records[\"community\"][\"CNAME\"][0], CNAME from records[\"community\"][\"CNAME\"][1], MX from records[\"community\"][\"MX\"][0]"]
    error_message = "The names are reported as CNAME conflicts"
  }
}

run "allowed_cname_conflicts_invalid_name" {
  command = plan

  variables {
    records                 = { "community" = { CNAME = [{ content = "target.example.net" }] } }
    allowed_cname_conflicts = ["community", "foo..bar", "with space"]
  }

  expect_failures = [var.allowed_cname_conflicts]
}

run "allowed_cname_conflicts_name_forms" {
  command = plan

  variables {
    records = {
      "community" = { CNAME = [{ content = "target.example.net" }], TXT = [{ content = "x" }] }
      "@"         = { TXT = [{ content = "y" }] }
    }
    allowed_cname_conflicts = ["Community.Example.com."]
  }

  assert {
    condition     = length(output.flat_records) == 3
    error_message = "A listed name may be fully qualified, in any case, with a trailing dot"
  }
}

run "allowed_cname_conflict_unused" {
  command = plan

  variables {
    records = {
      "community" = { CNAME = [{ content = "forum.example.net" }] }
    }
    allowed_cname_conflicts = ["community"]
  }

  expect_failures = [check.allowed_cname_conflicts_in_use]
}

run "names_in_lower_case" {
  command = plan

  variables {
    records = {
      "M1._domainkey" = { TXT = [{ content = "k=rsa; p=abc", key = "dkim" }] }
      "App"           = { "_X.TXT" = [{ content = "token", key = "x" }] }
    }
  }

  assert {
    condition = (
      output.flat_records["m1._domainkey TXT dkim"].name == "m1._domainkey"
      && output.flat_records["_x.app TXT x"].name == "_x.app"
    )
    error_message = "Names must be sent and keyed in lower case"
  }
}

run "mx_differing_only_in_priority" {
  command = plan

  variables {
    records = {
      "@" = { MX = [{ content = "mx.example.net", priority = 10 }, { content = "mx.example.net", priority = 20 }] }
    }
  }

  assert {
    condition     = output.diagnostics.duplicates == ["\"@ MX mx.example.net\" from records[\"@\"][\"MX\"][0] and records[\"@\"][\"MX\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}

run "mx_differing_only_in_priority_with_keys" {
  command = plan

  variables {
    records = {
      "@" = {
        MX = [
          { content = "mx.example.net", priority = 10, key = "primary" },
          { content = "mx.example.net", priority = 20, key = "backup" },
        ]
      }
    }
  }

  assert {
    condition     = length(output.flat_records) == 2
    error_message = "MX records differing only in priority are accepted with keys"
  }
}

run "aliases_under_a_fully_qualified_base_name" {
  command = plan

  variables {
    records = {
      "app.example.com" = {
        A             = [{ content = "192.0.2.1" }]
        ALIASES       = [{ name = "support" }]
        "cdn.ALIASES" = [{ name = "static" }]
        "_dmarc.TXT"  = [{ content = "v=DMARC1; p=none" }]
      }
      "example.com" = {
        ALIASES = [{ name = "www" }]
      }
    }
  }

  assert {
    condition = (
      output.flat_records["support CNAME"].content == "app.example.com"
      && output.flat_records["static CNAME"].content == "cdn.app.example.com"
      && output.flat_records["www CNAME"].content == "example.com"
      && one([for r in output.flat_records : r.name if r.type == "TXT"]) == "_dmarc.app.example.com"
    )
    error_message = "A fully qualified base name must not get the zone name appended again"
  }
}

run "hostnames_valid" {
  command = plan

  variables {
    records = {
      "www"    = { CNAME = [{ content = "Target-1.example.net." }] }
      "s1"     = { CNAME = [{ content = "s1._domainkey.mail.example.net" }] }
      "apex"   = { CNAME = [{ content = "@" }] }
      "@"      = { MX = [{ content = "mx1.example.net", priority = 10 }], NS = [{ content = "ns1.example.net" }] }
      "nomail" = { MX = [{ content = ".", priority = 0 }] }
      "1.2"    = { PTR = [{ content = "host.example.com." }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 7
    error_message = "Valid hostnames, @ and a null MX must be accepted"
  }
}

run "cname_with_spaces" {
  command = plan
  variables {
    records = { "www" = { CNAME = [{ content = "not a host" }] } }
  }
  expect_failures = [var.records]
}

run "cname_with_invalid_characters" {
  command = plan
  variables {
    records = { "www" = { CNAME = [{ content = "target!.example.net" }] } }
  }
  expect_failures = [var.records]
}

run "mx_with_an_ip_address" {
  command = plan
  variables {
    records = { "@" = { MX = [{ content = "192.0.2.10", priority = 10 }] } }
  }
  expect_failures = [var.records]
}

run "ns_with_a_label_over_63_characters" {
  command = plan
  variables {
    records = { "sub" = { NS = [{ content = "${join("", [for i in range(64) : "a"])}.example.net" }] } }
  }
  expect_failures = [var.records]
}

run "null_mx_only_for_mx" {
  command = plan
  variables {
    records = { "www" = { CNAME = [{ content = "." }] } }
  }
  expect_failures = [var.records]
}

run "ttl_below_60_without_enterprise" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "192.0.2.1", ttl = 45 }] } }
  }
  assert {
    condition     = output.diagnostics.low_ttls == ["\"app A 192.0.2.1\" (ttl 45) from records[\"app\"][\"A\"][0]"]
    error_message = "The TTLs are reported as below minimum_ttl"
  }

  assert {
    condition     = output.diagnostics.minimum_ttl == 60
    error_message = "The message of low_ttls names minimum_ttl"
  }
}

run "default_ttl_below_60_without_enterprise" {
  command = plan
  variables {
    default_ttl = 30
    records     = { "app" = { A = [{ content = "192.0.2.1" }] } }
  }
  assert {
    condition     = output.diagnostics.low_ttls == ["default_ttl (30)", "\"app A 192.0.2.1\" (ttl 30) from records[\"app\"][\"A\"][0]"]
    error_message = "The TTLs are reported as below minimum_ttl"
  }

  assert {
    condition     = output.diagnostics.minimum_ttl == 60
    error_message = "The message of low_ttls names minimum_ttl"
  }
}

run "ttl_below_60_on_enterprise" {
  command = plan
  variables {
    minimum_ttl = 30
    records     = { "app" = { A = [{ content = "192.0.2.1", ttl = 30 }], TXT = [{ content = "x", ttl = 45 }] } }
  }
  assert {
    condition     = output.flat_records["app A 192.0.2.1"].ttl == 30
    error_message = "minimum_ttl = 30 allows TTLs from 30 seconds"
  }
}

run "ttl_automatic_and_proxied" {
  command = plan
  variables {
    default_ttl = 1
    records = {
      "app" = { A = [{ content = "192.0.2.1" }] }
      "web" = { A = [{ content = "192.0.2.2", proxied = true, ttl = 300 }] }
    }
  }
  assert {
    condition     = output.flat_records["app A 192.0.2.1"].ttl == 1
    error_message = "TTL 1 (automatic) and proxied records are not affected by minimum_ttl"
  }
}

run "minimum_ttl_only_30_or_60" {
  command = plan
  variables {
    minimum_ttl = 45
    records     = { "app" = { A = [{ content = "192.0.2.1" }] } }
  }
  expect_failures = [var.minimum_ttl]
}

run "wildcard_valid_names" {
  command = plan

  variables {
    records = {
      "*"     = { A = [{ content = "192.0.2.1" }] }
      "*.app" = { A = [{ content = "192.0.2.2" }], ALIASES = [{ name = "legacy" }] }
      "app"   = { "_acme-challenge.TXT" = [{ content = "token" }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 4
    error_message = "A wildcard as the whole leftmost label is valid"
  }
}

run "wildcard_under_a_prefix" {
  command = plan
  variables {
    records = { "*" = { "_acme-challenge.TXT" = [{ content = "token" }] } }
  }
  assert {
    condition     = output.diagnostics.misplaced_wildcards == ["\"_acme-challenge.*\" from records[\"*\"][\"_acme-challenge.TXT\"][0]"]
    error_message = "The names are reported as names with a misplaced wildcard"
  }
}

run "wildcard_in_the_middle_after_combining" {
  command = plan
  variables {
    records = { "*.app" = { "x.A" = [{ content = "192.0.2.1" }] } }
  }
  assert {
    condition     = output.diagnostics.misplaced_wildcards == ["\"x.*.app\" from records[\"*.app\"][\"x.A\"][0]"]
    error_message = "The names are reported as names with a misplaced wildcard"
  }
}

run "wildcard_in_an_inline_alias_target" {
  command = plan
  variables {
    records = { "*.app" = { "cdn.ALIASES" = [{ name = "static" }] } }
  }
  assert {
    condition     = output.diagnostics.misplaced_wildcards == ["\"cdn.*.app\" from records[\"*.app\"][\"cdn.ALIASES\"][0] (alias target)"]
    error_message = "The names are reported as names with a misplaced wildcard"
  }
}

run "self_alias" {
  command = plan
  variables {
    records = { "app" = { ALIASES = [{ name = "app" }] } }
  }
  assert {
    condition     = output.diagnostics.self_cnames == ["\"app CNAME\" from records[\"app\"][\"ALIASES\"][0]"]
    error_message = "The records are reported as CNAMEs to their own name"
  }
}

run "self_cname_fully_qualified" {
  command = plan
  variables {
    records = { "www" = { CNAME = [{ content = "WWW.example.com." }] } }
  }
  assert {
    condition     = output.diagnostics.self_cnames == ["\"www CNAME\" from records[\"www\"][\"CNAME\"][0]"]
    error_message = "The records are reported as CNAMEs to their own name"
  }
}

run "self_cname_short" {
  command = plan
  variables {
    records = { "www" = { CNAME = [{ content = "www" }] } }
  }
  assert {
    condition     = output.diagnostics.self_cnames == ["\"www CNAME\" from records[\"www\"][\"CNAME\"][0]"]
    error_message = "The records are reported as CNAMEs to their own name"
  }
}

run "self_cname_apex" {
  command = plan
  variables {
    records = { "@" = { CNAME = [{ content = "@" }] } }
  }
  assert {
    condition     = output.diagnostics.self_cnames == ["\"@ CNAME\" from records[\"@\"][\"CNAME\"][0]"]
    error_message = "The records are reported as CNAMEs to their own name"
  }
}

run "cname_to_another_name" {
  command = plan

  variables {
    records = {
      "www" = { CNAME = [{ content = "app.example.com" }] }
      "@"   = { CNAME = [{ content = "lb.example.net" }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 2
    error_message = "A CNAME to another name is fine"
  }
}

run "default_ttl_below_minimum_even_if_unused" {
  command = plan
  variables {
    default_ttl = 30
    records     = { "app" = { A = [{ content = "192.0.2.1", ttl = 300 }] } }
  }
  assert {
    condition     = output.diagnostics.low_ttls == ["default_ttl (30)"]
    error_message = "The TTLs are reported as below minimum_ttl"
  }

  assert {
    condition     = output.diagnostics.minimum_ttl == 60
    error_message = "The message of low_ttls names minimum_ttl"
  }
}

run "default_ttl_30_on_enterprise" {
  command = plan

  variables {
    default_ttl = 30
    minimum_ttl = 30
    records     = { "app" = { A = [{ content = "192.0.2.1" }] } }
  }

  assert {
    condition     = output.flat_records["app A 192.0.2.1"].ttl == 30
    error_message = "default_ttl 30 is fine with minimum_ttl = 30"
  }
}

run "null_mx_with_priority_0" {
  command = plan
  variables {
    records = { "@" = { MX = [{ content = ".", priority = 0 }] } }
  }
  assert {
    condition     = output.flat_records["@ MX ."].priority == 0
    error_message = "A null MX with priority 0 is valid"
  }
}

run "null_mx_with_another_priority" {
  command = plan
  variables {
    records = { "@" = { MX = [{ content = ".", priority = 10 }] } }
  }
  expect_failures = [var.records]
}

run "fractional_ttl" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "192.0.2.1", ttl = 60.5 }] } }
  }
  expect_failures = [var.records]
}

run "fractional_priority" {
  command = plan
  variables {
    records = { "@" = { MX = [{ content = "mail.example.com", priority = 10.5 }] } }
  }
  expect_failures = [var.records]
}

run "priority_over_16_bits" {
  command = plan
  variables {
    records = { "@" = { MX = [{ content = "mail.example.com", priority = 65536 }] } }
  }
  expect_failures = [var.records]
}

# Each part is valid on its own; together with the prefix and the zone the name has
# 267 characters
run "fqdn_over_253_characters" {
  command = plan
  variables {
    records = { "${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}" = { "${join("", [for i in range(63) : "a"])}.TXT" = [{ content = "x" }] } }
  }
  assert {
    condition     = output.diagnostics.long_names == tolist(["\"${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.example.com\" (267 characters) from records[\"${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}\"][\"${join("", [for i in range(63) : "a"])}.TXT\"][0]"])
    error_message = "The names are reported as longer than 253 characters"
  }
}

run "fqdn_of_253_characters" {
  command = plan
  variables {
    # 3 x 63 + 49 + 4 dots + example.com (11) = 253
    records = { "${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}" = { "${join("", [for i in range(49) : "b"])}.TXT" = [{ content = "x" }] } }
  }
  assert {
    condition     = length(one(values(output.flat_records)).fqdn) == 253
    error_message = "A name of 253 characters is valid"
  }
}

# The alias target combines the prefix, the name and the zone: 267 characters
run "alias_target_over_253_characters" {
  command = plan
  variables {
    records = { "${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}" = { "${join("", [for i in range(63) : "a"])}.ALIASES" = [{ name = "www" }] } }
  }
  assert {
    condition     = output.diagnostics.long_names == tolist(["\"${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.example.com\" (267 characters), the target of \"www CNAME\" from records[\"${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}.${join("", [for i in range(63) : "a"])}\"][\"${join("", [for i in range(63) : "a"])}.ALIASES\"][0]"])
    error_message = "The names are reported as longer than 253 characters"
  }
}

# IPv6 addresses are keyed in their canonical form: the same address written twice is
# one key, a duplicate
run "ipv6_written_in_two_forms" {
  command = plan
  variables {
    records = { "app" = { AAAA = [{ content = "2001:db8::1" }, { content = "2001:0db8:0:0:0:0:0:1" }] } }
  }
  assert {
    condition     = output.diagnostics.duplicates == ["\"app AAAA 2001:db8::1\" from records[\"app\"][\"AAAA\"][0] and records[\"app\"][\"AAAA\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}

run "ipv6_sent_in_canonical_form" {
  command = plan
  variables {
    records = { "app" = { AAAA = [{ content = "2001:0DB8:0:0:0:0:0:1" }, { content = "::FFFF:C000:201" }] } }
  }
  assert {
    condition     = output.flat_records["app AAAA 2001:db8::1"].content == "2001:db8::1"
    error_message = "The key and the content have the canonical address"
  }
  assert {
    condition     = output.flat_records["app AAAA ::ffff:192.0.2.1"].content == "::ffff:192.0.2.1"
    error_message = "An IPv4-mapped address stays an IPv6 address, in the RFC 5952 form"
  }
}

run "ipv4_mapped_written_in_two_forms" {
  command = plan
  variables {
    records = { "app" = { AAAA = [{ content = "::ffff:192.0.2.1" }, { content = "::ffff:c000:201" }] } }
  }
  assert {
    condition     = output.diagnostics.duplicates == ["\"app AAAA ::ffff:192.0.2.1\" from records[\"app\"][\"AAAA\"][0] and records[\"app\"][\"AAAA\"][1]"]
    error_message = "The records are reported as duplicates"
  }
}


run "repeated_spf_and_dmarc_warn" {
  command = plan

  variables {
    records = {
      "@"      = { TXT = [{ content = "v=spf1 include:a.example -all" }, { content = "\"V=SPF1 mx\" \" -all\"" }, { content = "v=spf10 other" }] }
      "_dmarc" = { TXT = [{ content = "v=DMARC1; p=none" }, { content = "v=DMARC1;p=reject" }] }
      "mail"   = { TXT = [{ content = "v=spf1 -all" }] }
    }
  }

  expect_failures = [check.records_one_spf_and_dmarc_per_name]
}

run "one_spf_and_dmarc_per_name" {
  command = plan

  variables {
    records = {
      "@"      = { TXT = [{ content = "v=spf1 -all" }, { content = "google-site-verification=x" }] }
      "_dmarc" = { TXT = [{ content = "v=DMARC1; p=none" }] }
      "mail"   = { TXT = [{ content = "v=spf1 -all" }] }
    }
  }

  assert {
    condition     = length(local.repeated_policies) == 0
    error_message = "One SPF and one DMARC record per name do not warn"
  }
}

run "null_mx_with_other_mx_warns" {
  command = plan

  variables {
    records = {
      "@"           = { MX = [{ content = ".", priority = 0 }] }
      "example.com" = { MX = [{ content = "mx.example.net", priority = 10 }] }
      "nomail"      = { MX = [{ content = ".", priority = 0 }] }
    }
  }

  expect_failures = [check.records_null_mx_alone]
}

run "null_mx_alone" {
  command = plan

  variables {
    records = {
      "nomail" = { MX = [{ content = ".", priority = 0 }] }
      "mail"   = { MX = [{ content = "mx1.example.net", priority = 10 }, { content = "mx2.example.net", priority = 20 }] }
    }
  }

  assert {
    condition     = length(local.null_mx_with_others) == 0
    error_message = "A null MX alone and ordinary MX records do not warn"
  }
}

run "ipv4_leading_zero_first" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "010.1.1.1" }] } }
  }
  expect_failures = [var.records]
}

run "ipv4_leading_zero_second" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "192.00.2.1" }] } }
  }
  expect_failures = [var.records]
}

run "ipv4_leading_zero_third" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "192.0.002.1" }] } }
  }
  expect_failures = [var.records]
}

run "ipv4_leading_zero_fourth" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "192.0.2.01", key = "explicit" }] } }
  }
  expect_failures = [var.records]
}

run "ipv4_leading_zero_several" {
  command = plan
  variables {
    records = { "app" = { A = [{ content = "192.000.002.001" }] } }
  }
  expect_failures = [var.records]
}

run "ipv4_canonical_octets_keep_keys" {
  command = plan
  variables {
    records = { "app" = { A = [
      { content = "0.0.0.0" }, { content = "10.1.1.1" },
      { content = "192.0.2.1" }, { content = "255.255.255.255" },
    ] } }
  }
  assert {
    condition = toset(keys(output.flat_records)) == toset([
      "app A 0.0.0.0", "app A 10.1.1.1", "app A 192.0.2.1", "app A 255.255.255.255"
    ])
    error_message = "Canonical IPv4 values keep their existing state keys"
  }
}
