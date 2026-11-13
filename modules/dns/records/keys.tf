# Resolved records and their keys. The key is the Terraform address of a record
# ("<name> <TYPE> <value>"), so it depends on the value or on an explicit key, never on
# the position in a list: reordering records changes nothing, and a record with a key is
# updated in place when its value changes. The key is built from the normalized name and
# value, so forms of one record that DNS does not tell apart ("WWW" and "www", a target
# with or without the trailing dot) have one address.

locals {
  # Service parameters of HTTPS and SVCB records that can be set as fields of data, in
  # the order of their keys (mandatory 0, alpn 1, port 3, ipv4hint 4, ech 5, ipv6hint 6)
  svc_params = ["mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"]

  # Fields of data that hold hostnames (the target of a URI record is a URI, kept as
  # written: paths and queries are case-sensitive)
  hostname_fields = ["target", "replacement"]

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
    }
  ]

  # Canonical form of the IPv6 addresses, as Cloudflare stores them (cidrhost formats
  # them like RFC 5952: lower case, no leading zeros, the longest run of zeros as ::). An
  # IPv4-mapped address comes back as IPv4 and gets the ::ffff: prefix back
  # (::ffff:c000:201 is ::ffff:192.0.2.1); a value that is not an address (rejected by
  # the validation) stays as written, in lower case. Per record, not a map by address:
  # one address known only after apply (a record with a key) would make the map, and so
  # the keys of the other AAAA records, unknown
  addresses = [
    for r in local.resolved : r.type != "AAAA" ? null : (
      !can(cidrhost("${r.content}/128", 0)) ? lower(r.content) :
      strcontains(cidrhost("${r.content}/128", 0), ":") ? cidrhost("${r.content}/128", 0) :
      "::ffff:${cidrhost("${r.content}/128", 0)}"
    )
  ]

  # The normalized parts of the key, from the values as written (no zone name: the keys
  # must be known at plan also when the zone is not). The name in lower case without the
  # trailing dot; a short name is not made fully qualified, so "www" and
  # "www.example.com" stay two addresses (the checks report them as duplicates). The
  # value, by type:
  #   A, TXT, OPENPGPKEY  as written (TXT as a hash: text is case-sensitive)
  #   AAAA                the canonical IPv6 address (RFC 5952)
  #   MX, NS, PTR         the target in lower case without the trailing dot ("." and "@" as written)
  #   CAA                 the tag in lower case and the value as written
  #   CNAME               none: a name has one CNAME
  #   data types          a hash of data with numbers in their shortest form ("5060.0" is
  #                       5060), targets in lower case without the trailing dot (except
  #                       "."), and the service parameters of HTTPS and SVCB in value
  #   explicit key        the key as written
  normalized = [
    for i, r in local.resolved : {
      name = lower(trimsuffix(r.name, "."))
      value = (
        r.rec.key != null ? r.rec.key :
        r.type == "CNAME" ? null :
        r.type == "CAA" ? "${lower(r.rec.tag)} ${r.content}" :
        r.type == "TXT" ? substr(sha1(r.content), 0, 12) :
        r.type == "AAAA" ? local.addresses[i] :
        contains(["MX", "NS", "PTR"], r.type) ? (r.content == "." ? "." : lower(trimsuffix(r.content, "."))) :
        contains(local.data_types, r.type) ? substr(sha1(jsonencode(merge(
          {
            for field, value in r.rec.data : field => (
              value == null ? null :
              contains(lookup(local.numeric_fields, r.type, []), field) && can(tonumber(value)) ? tostring(tonumber(value)) :
              contains(local.hostname_fields, field) && !(field == "target" && r.type == "URI") && value != "." ? lower(trimsuffix(value, ".")) :
              value
            ) if !(contains(["HTTPS", "SVCB"], r.type) && contains(local.svc_params, field) && value != null)
          },
          contains(["HTTPS", "SVCB"], r.type) && length([for param in local.svc_params : param if lookup(r.rec.data, param, null) != null]) > 0 ? {
            value = join(" ", [for param in local.svc_params : "${param}=\"${param == "port" ? tonumber(r.rec.data[param]) : r.rec.data[param]}\"" if lookup(r.rec.data, param, null) != null])
          } : {},
        ))), 0, 12) :
        r.content
      )
    }
  ]

  # Keys follow the zone file format: "<name> <TYPE> <value>". legacy_key is the key of
  # the record in 2.x (the name and the value as written), for state_migration
  keyed = [
    for i, r in local.resolved : merge(r, {
      address = local.addresses[i]
      key     = local.normalized[i].value == null ? "${local.normalized[i].name} ${r.type}" : "${local.normalized[i].name} ${r.type} ${local.normalized[i].value}"
      legacy_key = (
        r.rec.key != null ? "${r.name} ${r.type} ${r.rec.key}" :
        r.type == "CNAME" ? "${r.name} CNAME" :
        r.type == "CAA" ? "${r.name} CAA ${r.rec.tag} ${r.content}" :
        r.type == "TXT" ? "${r.name} TXT ${local.normalized[i].value}" :
        contains(local.data_types, r.type) ? "${r.name} ${r.type} ${substr(sha1(jsonencode(r.rec.data)), 0, 12)}" :
        "${r.name} ${r.type} ${r.content}"
      )
    })
  ]

  records = [
    for r in local.keyed : {
      key        = r.key
      legacy_key = r.legacy_key
      source     = r.source
      name       = r.name
      fqdn       = local.fqdn[r.name]
      # An explicit key without its name part ("A main"), null for a key from the value
      explicit_key = r.rec.key != null ? "${r.type} ${r.rec.key}" : null
      type         = r.type
      # IPv6 addresses are sent in the canonical form, as Cloudflare stores them, and
      # "@" as a CNAME, MX, NS or PTR target as the zone name (the import compares it
      # with the name in the zone); the key keeps "@"
      content = (
        r.type == "CAA" || contains(local.data_types, r.type) ? null :
        r.type == "AAAA" ? r.address :
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
      # Cloudflare stores names in lower case
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

  # 2.x keys of the records whose key changed in 3.0, and their keys now, for moved
  # blocks (docs/upgrading.md). Grouped: records with one 2.x key are duplicates, which
  # the checks report
  legacy_keys     = { for r in local.records : r.legacy_key => r.key... if r.legacy_key != r.key }
  state_migration = { for legacy_key, keys in local.legacy_keys : legacy_key => keys[0] }
}
