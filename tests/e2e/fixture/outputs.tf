output "records" {
  description = "Records of all types supported by the provider v5"
  value = {
    (local.p) = {
      A = [{ content = var.a_value }, { content = "192.0.2.11", ttl = 600 }]
      # Not in the canonical form (2001:db8::10, ::ffff:192.0.2.10), which Cloudflare
      # stores: no drift and a match on import show that the module sends and compares
      # the canonical form
      AAAA          = [{ content = "2001:0DB8:0:0:0:0:0:10" }, { content = "::FFFF:C000:20A" }]
      TXT           = [{ content = "v=spf1 -all" }, { key = "rotating", content = var.txt_value }]
      MX            = [{ content = "mx.${local.z}", priority = 10 }]
      CAA           = [{ content = "letsencrypt.org", tag = "issue" }]
      "_dmarc.TXT"  = [{ content = "v=DMARC1; p=none" }]
      ALIASES       = [{ content = "alias.${local.p}" }]
      "www.ALIASES" = [{ content = "inline.${local.p}" }]
    }
    "proxied.${local.p}" = { CNAME = [{ content = "example.com", proxied = true }] }
    # Its content is changed outside Terraform by run.sh: the plan stays empty, and the
    # import scenario adopts it by name and type
    "acme.${local.p}" = { TXT = [{ key = "acme", content = "init", ignore_changes = ["content"] }] }
    # Its priority and port are changed outside Terraform: data and the top-level
    # priority of SRV are taken from the zone together
    "_xmpp._tcp.${local.p}" = {
      SRV = [{ key = "xmpp", data = { priority = 10, weight = 5, port = 5269, target = "xmpp.${local.z}" }, ignore_changes = ["content"] }]
    }
    "_sip._tcp.${local.p}" = {
      SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.${local.z}" } }]
    }
    "_ftp._tcp.${local.p}" = {
      URI = [{ priority = 10, data = { weight = 1, target = "ftp://ftp.example.com/" } }]
    }
    "svc.${local.p}" = {
      HTTPS = [{ data = { priority = 1, target = ".", value = "alpn=\"h2\"" } }]
      SVCB  = [{ data = { priority = 1, target = "svc.example.com", value = "port=\"8443\"" } }]
    }
    # Service parameters as fields: Cloudflare must store the value the module writes,
    # or the second plan and the import of this record fail
    "svc2.${local.p}" = {
      HTTPS = [{ data = { priority = 1, target = ".", alpn = "h3,h2", port = 443, ipv4hint = "192.0.2.1,192.0.2.2", ipv6hint = "2001:db8::1" } }]
    }
    "_25._tcp.${local.p}" = {
      TLSA = [{ data = { usage = 3, selector = 1, matching_type = 1, certificate = "0000000000000000000000000000000000000000000000000000000000000001" } }]
    }
    "ssh.${local.p}" = {
      SSHFP = [{ data = { algorithm = 4, type = 2, fingerprint = "0000000000000000000000000000000000000000000000000000000000000002" } }]
    }
    "naptr.${local.p}" = {
      NAPTR = [{ data = { order = 100, preference = 10, flags = "U", service = "E2U+sip", regex = "!^.*$!sip:info@example.com!", replacement = "." } }]
    }
    "loc.${local.p}" = {
      LOC = [{ data = { lat_degrees = 59, lat_minutes = 26, lat_seconds = 14, lat_direction = "N", long_degrees = 24, long_minutes = 44, long_seconds = 43, long_direction = "E", altitude = 30, size = 1, precision_horz = 10, precision_vert = 10 } }]
    }
  }
}

output "migration_records" {
  description = "Records used to check the migration from provider v4 to v5"
  value = {
    "m-${local.p}" = {
      A       = [{ content = "192.0.2.30" }]
      TXT     = [{ content = "v=spf1 -all" }]
      MX      = [{ content = "mx.${local.z}", priority = 10 }]
      CAA     = [{ content = "letsencrypt.org", tag = "issue" }]
      ALIASES = [{ content = "m-alias-${local.p}" }]
    }
    "_sip._tcp.m-${local.p}" = {
      SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.${local.z}" } }]
    }
  }
}
