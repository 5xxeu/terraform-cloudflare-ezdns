# Normalized keys: forms of one record that DNS does not tell apart have one address,
# and a record written in the canonical form keeps the key it had in 2.x. The keys and
# the 2.x keys below were checked against v2.22.0 on the same fixtures

variables {
  root_domain = "example.com"
}

# One record of each class (A, AAAA, CNAME and ALIASES, MX, NS, PTR, CAA, TXT, data
# types, an explicit key) in the canonical form: the keys of 2.x, nothing to migrate
run "canonical_keys_as_in_2x" {
  command = plan

  variables {
    records = yamldecode(file("tests/fixtures/keys-canonical.yaml"))["records"]
  }

  assert {
    condition = keys(output.flat_records) == [
      "1.2 PTR host.example.com",
      "@ CAA issue letsencrypt.org",
      "@ HTTPS 2563d6f5901e",
      "@ MX mail.example.com",
      "@ TXT d2b1e35921ca",
      "_25._tcp.mail TLSA 7e70da337f89",
      "_sip._tcp SRV 9c61601f99e8",
      "_web._tcp URI 8b8dfee6118d",
      "app A 192.0.2.1",
      "app AAAA 2001:db8::1",
      "app TXT dkim",
      "nomail MX .",
      "office LOC 46ecfa803924",
      "relay MX @",
      "sip NAPTR 9162c6c146d3",
      "static CNAME",
      "sub NS ns1.example.net",
      "svc SVCB 8d99af72d5c0",
      "v4m AAAA ::ffff:192.0.2.1",
      "www CNAME",
      "www2 CNAME",
    ]
    error_message = "Records in the canonical form must keep their 2.x keys"
  }

  assert {
    condition     = output.state_migration == {}
    error_message = "Records in the canonical form have nothing to migrate"
  }
}

# The same records in other forms (names in upper case, targets with the trailing dot,
# IPv6 not shortened, numbers as decimals, HTTPS service parameters as fields), each
# planned on its own: the addresses of their canonical forms
run "other_forms_same_keys" {
  command = plan

  variables {
    records = yamldecode(file("tests/fixtures/keys-forms.yaml"))["records"]
  }

  assert {
    condition     = length(setsubtract(keys(output.flat_records), keys(run.canonical_keys_as_in_2x.flat_records))) == 0 && length(output.flat_records) == 16
    error_message = "Every form must have the address of its canonical form"
  }

  assert {
    condition = output.state_migration == {
      "1.2 PTR Host.Example.com."      = "1.2 PTR host.example.com"
      "@ HTTPS eb0e3fa8c313"           = "@ HTTPS 2563d6f5901e"
      "@ MX Mail.Example.com."         = "@ MX mail.example.com"
      "APP A 192.0.2.1"                = "app A 192.0.2.1"
      "APP AAAA 2001:0DB8:0:0:0:0:0:1" = "app AAAA 2001:db8::1"
      "APP TXT dkim"                   = "app TXT dkim"
      "Static CNAME"                   = "static CNAME"
      "Sub NS NS1.example.net."        = "sub NS ns1.example.net"
      "V4M AAAA ::ffff:c000:201"       = "v4m AAAA ::ffff:192.0.2.1"
      "WWW CNAME"                      = "www CNAME"
      "WWW2 CNAME"                     = "www2 CNAME"
      "_SIP._tcp SRV ebb29c51d740"     = "_sip._tcp SRV 9c61601f99e8"
      "_web._tcp URI bdb1f67a8194"     = "_web._tcp URI 8b8dfee6118d"
      "office LOC 44bf1db748bf"        = "office LOC 46ecfa803924"
      "svc SVCB 3af14752662a"          = "svc SVCB 8d99af72d5c0"
    }
    error_message = "state_migration must map the 2.x keys of the other forms to their keys now"
  }
}

# What stays as written: TXT text, the value of CAA, URI targets, hex strings, explicit
# keys, and a short name next to the fully qualified one
run "kept_as_written" {
  command = plan

  variables {
    records = {
      "app" = {
        TXT = [{ content = "Token" }, { content = "token" }, { content = "a", key = "Dkim" }, { content = "b", key = "dkim" }]
        CAA = [{ content = "LetsEncrypt.org", tag = "issue" }]
      }
      "_25._tcp.mail" = { TLSA = [{ data = { usage = 3, selector = 1, matching_type = 1, certificate = "ABCDEF" } }] }
    }
  }

  assert {
    condition = keys(output.flat_records) == [
      "_25._tcp.mail TLSA ${substr(sha1(jsonencode({ certificate = "ABCDEF", matching_type = "1", selector = "1", usage = "3" })), 0, 12)}",
      "app CAA issue LetsEncrypt.org",
      "app TXT Dkim",
      "app TXT ${substr(sha1("Token"), 0, 12)}",
      "app TXT dkim",
      "app TXT ${substr(sha1("token"), 0, 12)}",
    ]
    error_message = "TXT text, CAA values, hex strings and explicit keys must be kept as written"
  }
}

# Two forms of one record in one configuration have one key, so they are duplicates
run "two_forms_in_one_configuration" {
  command = plan

  variables {
    records = {
      "www" = { A = [{ content = "192.0.2.1" }] }
      "WWW" = { A = [{ content = "192.0.2.1" }], AAAA = [{ content = "2001:db8::1" }, { content = "2001:DB8:0::1" }] }
    }
  }

  assert {
    condition = output.diagnostics.duplicates == [
      "\"www A 192.0.2.1\" from records[\"WWW\"][\"A\"][0] and records[\"www\"][\"A\"][0]",
      "\"www AAAA 2001:db8::1\" from records[\"WWW\"][\"AAAA\"][0] and records[\"WWW\"][\"AAAA\"][1]",
    ]
    error_message = "Two forms of one record must be reported as duplicates of one key"
  }

  assert {
    condition     = output.state_migration == { "WWW A 192.0.2.1" = "www A 192.0.2.1", "WWW AAAA 2001:db8::1" = "www AAAA 2001:db8::1", "WWW AAAA 2001:DB8:0::1" = "www AAAA 2001:db8::1" }
    error_message = "Duplicates must not fail state_migration"
  }
}

# The same 2.x key twice (a duplicate in 2.x too) is one entry of state_migration
run "same_legacy_key_twice" {
  command = plan

  variables {
    records = { "WWW" = { A = [{ content = "192.0.2.1" }, { content = "192.0.2.1" }] } }
  }

  assert {
    condition     = output.state_migration == { "WWW A 192.0.2.1" = "www A 192.0.2.1" }
    error_message = "A repeated 2.x key must not fail state_migration"
  }

  assert {
    condition     = length(output.diagnostics.duplicates) == 1
    error_message = "The records are reported as duplicates"
  }
}
