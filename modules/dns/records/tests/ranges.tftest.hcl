# Ranges of the numeric fields of data and of CAA flags: values at the limits pass,
# values beyond them and values that are not numbers fail at plan.

variables {
  root_domain = "example.com"
}

run "limits_pass" {
  command = plan

  variables {
    records = {
      "_sip._tcp" = { SRV = [
        { key = "low", data = { priority = 0, weight = 0, port = 0, target = "." } },
        { key = "high", data = { priority = 65535, weight = 65535, port = 65535, target = "sip.example.com" } },
      ] }
      "_ftp._tcp"     = { URI = [{ priority = 10, data = { weight = 65535, target = "ftp://ftp.example.com/" } }] }
      "@"             = { HTTPS = [{ data = { priority = 65535, target = "." } }], CAA = [{ content = "letsencrypt.org", tag = "issue", flags = 255 }] }
      "_25._tcp.mail" = { TLSA = [{ data = { usage = 255, selector = 255, matching_type = 255, certificate = "ab" } }] }
      "host"          = { SSHFP = [{ data = { algorithm = 255, type = 255, fingerprint = "ab" } }] }
      "child"         = { DS = [{ data = { key_tag = 65535, algorithm = 255, digest_type = 255, digest = "ab" } }] }
      "keys"          = { DNSKEY = [{ data = { flags = 65535, protocol = 3, algorithm = 255, public_key = "ab" } }] }
      "cert"          = { CERT = [{ data = { type = 65535, key_tag = 65535, algorithm = 255, certificate = "ab" } }] }
      "sip"           = { NAPTR = [{ data = { order = 65535, preference = 65535, flags = "S", service = "SIP+D2U", regex = "", replacement = "_sip._udp.example.com" } }] }
      "south" = { LOC = [{ data = {
        lat_degrees  = 90, lat_minutes = 59, lat_seconds = 59.999, lat_direction = "S",
        long_degrees = 180, long_minutes = 59, long_seconds = 59.999, long_direction = "W",
        altitude     = -100000, size = 90000000, precision_horz = 0, precision_vert = 90000000,
      } }] }
      # An unquoted N in YAML 1.1 arrives as "false"
      "north" = { LOC = [{ data = {
        lat_degrees  = 0, lat_minutes = 0, lat_seconds = 0, lat_direction = "false",
        long_degrees = 0, long_minutes = 0, long_seconds = 0, long_direction = "E",
        altitude     = 42849672.95,
      } }] }
    }
  }

  assert {
    condition     = length(output.flat_records) == 13
    error_message = "Records with data at the limits of their ranges must be accepted"
  }
}

run "srv_port_over_16_bits" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = 70000, target = "sip.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_weight_negative" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = -1, port = 5060, target = "sip.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_port_not_a_number" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 10, weight = 5, port = "sip", target = "sip.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "srv_priority_fractional" {
  command = plan

  variables {
    records = { "_sip._tcp" = { SRV = [{ data = { priority = 1.5, weight = 5, port = 5060, target = "sip.example.com" } }] } }
  }

  expect_failures = [var.records]
}

run "uri_weight_over_16_bits" {
  command = plan

  variables {
    records = { "_ftp._tcp" = { URI = [{ priority = 10, data = { weight = 65536, target = "ftp://ftp.example.com/" } }] } }
  }

  expect_failures = [var.records]
}

run "https_priority_over_16_bits" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 65536, target = "." } }] } }
  }

  expect_failures = [var.records]
}

run "tlsa_usage_over_8_bits" {
  command = plan

  variables {
    records = { "_25._tcp.mail" = { TLSA = [{ data = { usage = 256, selector = 1, matching_type = 1, certificate = "ab" } }] } }
  }

  expect_failures = [var.records]
}

run "sshfp_type_over_8_bits" {
  command = plan

  variables {
    records = { "host" = { SSHFP = [{ data = { algorithm = 4, type = 300, fingerprint = "ab" } }] } }
  }

  expect_failures = [var.records]
}

run "ds_key_tag_over_16_bits" {
  command = plan

  variables {
    records = { "child" = { DS = [{ data = { key_tag = 70000, algorithm = 13, digest_type = 2, digest = "ab" } }] } }
  }

  expect_failures = [var.records]
}

run "dnskey_algorithm_over_8_bits" {
  command = plan

  variables {
    records = { "keys" = { DNSKEY = [{ data = { flags = 257, protocol = 3, algorithm = 256, public_key = "ab" } }] } }
  }

  expect_failures = [var.records]
}

run "cert_type_not_a_number" {
  command = plan

  variables {
    records = { "cert" = { CERT = [{ data = { type = "PKIX", key_tag = 0, algorithm = 0, certificate = "ab" } }] } }
  }

  expect_failures = [var.records]
}

run "naptr_order_over_16_bits" {
  command = plan

  variables {
    records = { "sip" = { NAPTR = [{ data = { order = 65536, preference = 10, replacement = "." } }] } }
  }

  expect_failures = [var.records]
}

run "loc_lat_degrees_over_90" {
  command = plan

  variables {
    records = { "office" = { LOC = [{ data = { lat_degrees = 91, lat_minutes = 0, lat_seconds = 0, lat_direction = "N", long_degrees = 24, long_minutes = 0, long_seconds = 0, long_direction = "E" } }] } }
  }

  expect_failures = [var.records]
}

run "loc_long_minutes_fractional" {
  command = plan

  variables {
    records = { "office" = { LOC = [{ data = { lat_degrees = 59, lat_minutes = 0, lat_seconds = 0, lat_direction = "N", long_degrees = 24, long_minutes = 1.5, long_seconds = 0, long_direction = "E" } }] } }
  }

  expect_failures = [var.records]
}

run "loc_direction_swapped" {
  command = plan

  variables {
    records = { "office" = { LOC = [{ data = { lat_degrees = 59, lat_minutes = 0, lat_seconds = 0, lat_direction = "E", long_degrees = 24, long_minutes = 0, long_seconds = 0, long_direction = "N" } }] } }
  }

  expect_failures = [var.records]
}

run "caa_flags_over_8_bits" {
  command = plan

  variables {
    records = { "@" = { CAA = [{ content = "letsencrypt.org", tag = "issue", flags = 256 }] } }
  }

  expect_failures = [var.records]
}

# Service parameters of HTTPS and SVCB records as fields of data

run "svc_params_written_into_value" {
  command = plan

  variables {
    records = {
      "@"   = { HTTPS = [{ data = { priority = 1, target = ".", ipv6hint = "2001:db8::1", alpn = "h3,h2", port = 443, ipv4hint = "192.0.2.1,192.0.2.2" } }] }
      "svc" = { SVCB = [{ data = { priority = 1, target = "svc.example.net", mandatory = "alpn", alpn = "h2" } }] }
    }
  }

  assert {
    condition     = output.flat_records["@ HTTPS ${substr(sha1(jsonencode({ priority = "1", target = ".", ipv6hint = "2001:db8::1", alpn = "h3,h2", port = "443", ipv4hint = "192.0.2.1,192.0.2.2" })), 0, 12)}"].data == tomap({ priority = "1", target = ".", value = "alpn=\"h3,h2\" port=\"443\" ipv4hint=\"192.0.2.1,192.0.2.2\" ipv6hint=\"2001:db8::1\"" })
    error_message = "Parameters must be written into value in the order of their keys, and left out of data"
  }

  assert {
    condition     = [for r in output.flat_records : r.data.value if r.type == "SVCB"] == ["mandatory=\"alpn\" alpn=\"h2\""]
    error_message = "mandatory comes first"
  }
}

run "svc_value_as_written" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", value = "alpn=h2" } }] } }
  }

  assert {
    condition     = [for r in output.flat_records : r.data.value] == ["alpn=h2"]
    error_message = "value without parameter fields stays as written"
  }
}

run "svc_value_and_params" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", value = "alpn=h2", port = 443 } }] } }
  }

  expect_failures = [var.records]
}

run "svc_params_and_value_are_one_record" {
  command = plan

  variables {
    records = {
      "@" = {
        HTTPS = [
          { data = { priority = 1, target = ".", value = "alpn=\"h2\" port=\"443\"" } },
          { data = { priority = 1, target = ".", alpn = "h2", port = 443 } },
        ]
      }
    }
  }

  expect_failures = [output.flat_records]
}

run "svc_port_as_a_decimal_number" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", port = "443.0" } }] } }
  }

  assert {
    condition     = [for r in output.flat_records : r.data.value] == ["port=\"443\""]
    error_message = "port must be written as a decimal number"
  }
}

run "svc_mandatory_not_set" {
  command = plan

  variables {
    records = {
      "@"   = { HTTPS = [{ data = { priority = 1, target = ".", mandatory = "port", alpn = "h2" } }] }
      "www" = { HTTPS = [{ data = { priority = 1, target = ".", mandatory = "alpn,alpn", alpn = "h2" } }] }
    }
  }

  expect_failures = [var.records]
}

run "svc_ech_not_padded" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", ech = "A===" } }] } }
  }

  expect_failures = [var.records]
}

run "svc_empty_params" {
  command = plan

  variables {
    records = {
      "@"    = { HTTPS = [{ data = { priority = 1, target = ".", alpn = "" } }] }
      "svc"  = { SVCB = [{ data = { priority = 1, target = ".", ech = "" } }] }
      "svc2" = { SVCB = [{ data = { priority = 1, target = ".", ipv4hint = "" } }] }
    }
  }

  expect_failures = [var.records]
}

run "svc_alpn_with_spaces" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", alpn = "h3, h2" } }] } }
  }

  expect_failures = [var.records]
}

run "svc_ipv4hint_not_ipv4" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", ipv4hint = "192.0.2.1,2001:db8::1" } }] } }
  }

  expect_failures = [var.records]
}

run "svc_ipv6hint_not_ipv6" {
  command = plan

  variables {
    records = { "@" = { SVCB = [{ data = { priority = 1, target = ".", ipv6hint = "192.0.2.1" } }] } }
  }

  expect_failures = [var.records]
}

run "svc_mandatory_unknown_key" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", mandatory = "alpn,foo", alpn = "h2" } }] } }
  }

  expect_failures = [var.records]
}

run "svc_port_over_16_bits" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", port = 70000 } }] } }
  }

  expect_failures = [var.records]
}

run "svc_ech_not_base64" {
  command = plan

  variables {
    records = { "@" = { HTTPS = [{ data = { priority = 1, target = ".", ech = "not base64!" } }] } }
  }

  expect_failures = [var.records]
}
