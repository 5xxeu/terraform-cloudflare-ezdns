# The v5 wrapper with internationalized names: zone_name, names, prefixes of record
# types and targets in Unicode are converted to Punycode with provider::idna::to_ascii,
# then everything goes to the v5 wrapper, called "v5" like in the root module, so the
# records have the same addresses. Only values with non-ASCII characters are converted:
# to_ascii also writes ASCII names in lower case, which would change the keys of names
# written in another case. Everything else is passed as written, so the v5 wrapper
# checks the input as given; an input that is not a map of records is passed unchanged
# and fails there.
#
# No try() over the records: try() returns an unknown result for a value that is not
# wholly known, so one value computed by another resource (a TTL, the DNS name of a
# load balancer) would make every name and key unknown. Errors are avoided with can()
# over the shape of the input (names, types and attribute names, which are known)
# and conditionals instead.

locals {
  # Record types whose content is a name (ALIASES name the CNAME by their content)
  name_content_kinds = ["CNAME", "MX", "NS", "PTR", "ALIASES"]

  # Scheme with user information, host and the rest of a URI target; only the host is
  # a name
  uri = "^([A-Za-z][A-Za-z0-9+.-]*://(?:[^/?#@]*@)?)([^/:?#@]+)(.*)$"

  # records and the records of each group, by their origin; a group without records
  # stays as written, so the v5 wrapper reports it
  inputs = merge(
    { records = var.records },
    { for group, g in var.record_groups : "group:${group}" => g.records if can(keys(g)) ? contains(keys(g), "records") : false },
  )

  # Whether the input has the shape of records (maps of names, types, lists of objects)
  valid = can([
    for records in values(local.inputs) : [
      for name, types in records : [
        for type, list in types : [for record in list : keys(record)]
      ]
    ]
  ])

  # Every name of the input that is part of a key and may need converting. Targets,
  # zone_name, allowed_cname_conflicts and owned_names are converted where they are
  # (below), not looked up here: a value known only after apply (the DNS name of a load
  # balancer, a zone created in the same apply) would make this table, and so every
  # name and key, unknown
  names = try(distinct(compact(flatten([
    [
      for records in values(local.inputs) : [
        for name, types in records : [
          name,
          [
            for type, list in types : [
              for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
                length(split(".", type)) > 1 ? join(".", slice(split(".", type), 0, length(split(".", type)) - 1)) : "",
              ]
            ]
          ],
        ]
      ]
    ],
  ]))), [])
  ascii = { for n in local.names : n => can(regex("[^[:ascii:]]", n)) ? provider::idna::to_ascii(n) : n }

  # One entry per name and type of each origin, with the records converted
  entries = !local.valid ? null : flatten([
    for origin, records in local.inputs : [
      for name, types in records : [
        for type, list in types : [
          for kind in [element(split(".", type), length(split(".", type)) - 1)] : {
            origin = origin
            name   = local.ascii[name]
            type   = length(split(".", type)) > 1 ? "${local.ascii[join(".", slice(split(".", type), 0, length(split(".", type)) - 1))]}.${kind}" : type
            # The conditions depend only on the attributes present, never on the values,
            # so an unknown target stays an unknown value of a known record. A target
            # without non-ASCII characters (also null) is kept as written
            list = [
              for record in list : merge(
                record,
                contains(local.name_content_kinds, kind) && contains(keys(record), "content") ? {
                  content = can(regex("[^[:ascii:]]", record.content)) ? provider::idna::to_ascii(record.content) : record.content
                } : {},
                contains(["SRV", "HTTPS", "SVCB"], kind) && try(contains(keys(record.data), "target"), false) ? {
                  data = merge(record.data, { target = can(regex("[^[:ascii:]]", record.data.target)) ? provider::idna::to_ascii(record.data.target) : record.data.target })
                } : {},
                kind == "NAPTR" && try(contains(keys(record.data), "replacement"), false) ? {
                  data = merge(record.data, { replacement = can(regex("[^[:ascii:]]", record.data.replacement)) ? provider::idna::to_ascii(record.data.replacement) : record.data.replacement })
                } : {},
                # Only the host of a URI target is a name
                kind == "URI" && try(contains(keys(record.data), "target"), false) ? {
                  data = merge(record.data, {
                    target = can(regex("[^[:ascii:]]", regex(local.uri, record.data.target)[1])) ? join("", [
                      for i, part in regex(local.uri, record.data.target) : i == 1 ? provider::idna::to_ascii(part) : part
                    ]) : record.data.target
                  })
                } : {},
              )
            ]
          }
        ]
      ]
    ]
  ])

  # Names and type keys that differ only in their form ("bücher" and "xn--bcher-kva")
  # are joined, like the same name written twice; the v5 wrapper then finds duplicates.
  # The entries are grouped by origin and name once, so the work grows linearly with
  # the names (origins and types are few); names and origins have no newlines
  grouped = local.entries == null ? null : { for e in local.entries : "${e.origin}\n${e.name}" => e... }
  converted = local.entries == null ? null : {
    for origin in keys(local.inputs) : origin => {
      for k, es in local.grouped : es[0].name => {
        for type in distinct([for e in es : e.type]) : type => flatten([for e in es : e.list if e.type == type])
      } if es[0].origin == origin
    }
  }

  # The converted value has other attribute names than the input, so the two cannot be
  # unified into one type by a conditional: one of them is picked from a tuple instead
  records = concat(
    [for x in [0] : local.converted["records"] if local.valid],
    [for x in [0] : var.records if !local.valid],
  )[0]
  converted_groups = { for group, g in var.record_groups : group => local.valid ? contains(keys(local.converted), "group:${group}") : false }
  record_groups = {
    for group, g in var.record_groups : group => concat(
      [for x in [g] : merge(x, { records = local.converted["group:${group}"] }) if local.converted_groups[group]],
      [for x in [g] : x if !local.converted_groups[group]],
    )[0]
  }

  # Cloudflare returns the name of an internationalized zone in Unicode, so the zone is
  # looked up here, with its name converted, instead of in the v5 wrapper. coalesce makes
  # a name known only after apply (a zone_id from a resource, a computed zone_name) a value that is not null
  # at plan, so the v5 wrapper knows at plan that it needs no lookup of its own
  zone_name = coalesce(var.zone_name != null ? (can(regex("[^[:ascii:]]", var.zone_name)) ? provider::idna::to_ascii(var.zone_name) : var.zone_name) : provider::idna::to_ascii(data.cloudflare_zone.this[0].name), "")
}

data "cloudflare_zone" "this" {
  count   = var.zone_name == null ? 1 : 0
  zone_id = var.zone_id
}

module "v5" {
  source = "../v5"

  zone_id                 = var.zone_id
  zone_name               = local.zone_name
  records                 = local.records
  record_groups           = local.record_groups
  import_existing         = var.import_existing
  report_unmanaged        = var.report_unmanaged
  unmanaged_ignore        = var.unmanaged_ignore
  unmanaged_policy        = var.unmanaged_policy
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = [for n in var.allowed_cname_conflicts : can(regex("[^[:ascii:]]", n)) ? provider::idna::to_ascii(n) : n]
  minimum_ttl             = var.minimum_ttl
  require_keys            = var.require_keys
  owned_names = var.owned_names == null ? null : {
    include = [for n in var.owned_names.include : can(regex("[^[:ascii:]]", n)) ? provider::idna::to_ascii(n) : n]
    exclude = [for n in var.owned_names.exclude : can(regex("[^[:ascii:]]", n)) ? provider::idna::to_ascii(n) : n]
  }
}
