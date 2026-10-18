# Resolved records and their keys. The key is the Terraform address of a record
# ("<name> <TYPE> <value>"), so it depends on the value or on an explicit key, never on
# the position in a list: reordering records changes nothing, and a record with a key is
# updated in place when its value changes.

locals {
  # Service parameters of HTTPS and SVCB records that can be set as fields of data, in
  # the order of their keys (mandatory 0, alpn 1, port 3, ipv4hint 4, ech 5, ipv6hint 6)
  svc_params = ["mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"]

  # Resolved records: ALIASES become CNAMEs, prefixes are prepended to the base name
  resolved = [
    for i, e in local.entries : {
      rec    = e.rec
      source = e.source
      name   = local.entry_names[i]
      type   = e.kind == "ALIASES" ? "CNAME" : e.kind
      # Alias targets are the fully qualified base name, so "app" and
      # "app.example.com" both point to app.example.com
      content = e.kind == "ALIASES" ? (e.prefix == null ? local.qualified[e.base_name] : "${e.prefix}.${local.qualified[e.base_name]}") : e.rec.content

      # Key used by module versions 1.x, for state migration
      old_key = (
        e.kind == "ALIASES" && e.prefix == null ? "ALIASES_${e.base_name}_${e.rec.content}" :
        e.kind == "ALIASES" ? "ALIASES_INLINE_${e.base_name}_${e.raw_key}_${e.idx}_${e.rec.content}" :
        e.raw_key == "CAA" ? "CAA_${e.base_name}_${e.rec.tag}_${e.rec.content}_${e.rec.flags}" :
        "${e.raw_key}_${e.base_name}_${e.idx}"
      )
    }
  ]

  # Canonical form of the configured IPv6 addresses (cidrhost formats them like
  # RFC 5952: lower case, no leading zeros, the longest run of zeros as ::). An
  # IPv4-mapped address comes back as IPv4 and gets the ::ffff: prefix back
  # (::ffff:c000:201 is ::ffff:192.0.2.1); a value that is not an address (rejected
  # by the validation) stays as written, in lower case
  canonical_ipv6 = {
    for address in distinct([for r in local.resolved : r.content if r.type == "AAAA"]) : address => (
      !can(cidrhost("${address}/128", 0)) ? lower(address) :
      strcontains(cidrhost("${address}/128", 0), ":") ? cidrhost("${address}/128", 0) :
      "::ffff:${cidrhost("${address}/128", 0)}"
    )
  }

  # Keys follow the zone file format: "<name> <TYPE> <value>"
  keyed = [
    for r in local.resolved : merge(r, {
      key = (
        r.rec.key != null ? "${r.name} ${r.type} ${r.rec.key}" :
        r.type == "CNAME" ? "${r.name} CNAME" :
        r.type == "CAA" ? "${r.name} CAA ${r.rec.tag} ${r.content}" :
        r.type == "TXT" ? "${r.name} TXT ${substr(sha1(r.content), 0, 12)}" :
        contains(local.data_types, r.type) ? "${r.name} ${r.type} ${substr(sha1(jsonencode(r.rec.data)), 0, 12)}" :
        "${r.name} ${r.type} ${r.content}"
      )
    })
  ]

  records = [
    for r in local.keyed : {
      key     = r.key
      old_key = r.old_key
      source  = r.source
      name    = r.name
      fqdn    = local.fqdn[r.name]
      # An explicit key without its name part ("A main"), null for a key from the value
      explicit_key = r.rec.key != null ? trimprefix(r.key, "${r.name} ") : null
      type         = r.type
      # IPv6 addresses are sent in the canonical form, as Cloudflare stores them, and
      # "@" as a CNAME, MX, NS or PTR target as the zone name (the import compares it
      # with the name in the zone); the key keeps the value as written
      content = (
        r.type == "CAA" || contains(local.data_types, r.type) ? null :
        r.type == "AAAA" ? local.canonical_ipv6[r.content] :
        contains(["CNAME", "MX", "NS", "PTR"], r.type) && r.content == "@" ? local.zone :
        r.content
      )
      ttl = coalesce(r.rec.ttl, var.default_ttl)
      proxied = (
        r.rec.proxied != null ? r.rec.proxied :
        contains(["A", "AAAA", "CNAME"], r.type) ? var.default_proxied :
        false
      )
      comment         = r.rec.comment != null ? r.rec.comment : var.default_comment
      tags            = distinct(concat(var.default_tags, coalesce(r.rec.tags, [])))
      settings        = r.rec.settings
      private_routing = r.rec.private_routing
      ignore_changes  = sort(distinct(coalesce(r.rec.ignore_changes, [])))
      priority        = contains(["MX", "URI"], r.type) ? r.rec.priority : r.type == "SRV" ? tonumber(r.rec.data.priority) : null
      data = (
        r.type == "CAA" ? tomap({ flags = tostring(r.rec.flags), tag = r.rec.tag, value = r.content }) :
        # Cloudflare returns SVCB and HTTPS targets as fully qualified names, so they
        # get the trailing dot here to avoid a diff on every plan. Service parameters
        # set as fields go into value, in the order of their keys (RFC 9460), port as a
        # decimal number ("443.0" is 443)
        contains(["HTTPS", "SVCB"], r.type) ? merge(
          { for field, value in r.rec.data : field => value if !contains(local.svc_params, field) },
          { target = endswith(r.rec.data.target, ".") ? r.rec.data.target : "${r.rec.data.target}." },
          length([for param in local.svc_params : param if lookup(r.rec.data, param, null) != null]) == 0 ? {} : {
            value = join(" ", [for param in local.svc_params : "${param}=\"${param == "port" ? tonumber(r.rec.data[param]) : r.rec.data[param]}\"" if lookup(r.rec.data, param, null) != null])
          },
        ) :
        # yamldecode reads an unquoted N as false (YAML 1.1); for LOC it can only mean north
        r.type == "LOC" ? merge(r.rec.data, lookup(r.rec.data, "lat_direction", "") == "false" ? { lat_direction = "N" } : {}) :
        contains(local.data_types, r.type) ? r.rec.data :
        null
      )
    }
  ]

  grouped = { for r in local.records : r.key => r... }

  flat_records = {
    for key, group in local.grouped : key => {
      # Cloudflare stores names in lower case; the key keeps the name as written
      name            = lower(group[0].name)
      fqdn            = group[0].fqdn
      type            = group[0].type
      content         = group[0].content
      ttl             = group[0].ttl
      proxied         = group[0].proxied
      comment         = group[0].comment
      tags            = group[0].tags
      settings        = group[0].settings
      private_routing = group[0].private_routing
      ignore_changes  = group[0].ignore_changes
      priority        = group[0].priority
      data            = group[0].data
    }
  }

  state_migration = {
    for r in local.records : r.old_key => r.key if r.old_key != r.key
  }
}
