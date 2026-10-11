# The v5 wrapper with internationalized names: zone_name, names, prefixes of record
# types and targets in Unicode are converted to Punycode with provider::idna::to_ascii,
# then everything goes to the v5 wrapper, called "v5" like in the root module, so the
# records have the same addresses. Only values with non-ASCII characters are converted:
# to_ascii also writes ASCII names in lower case, which would change the keys of names
# written in another case. Everything else is passed as written, so the v5 wrapper
# checks the input as given; an input that is not a map of records is passed unchanged
# and fails there.

locals {
  # Record types whose content is a name (ALIASES name the CNAME by their content)
  name_content_kinds = ["CNAME", "MX", "NS", "PTR", "ALIASES"]

  # Scheme, host and the rest of a URI target; only the host is a name
  uri = "^([A-Za-z][A-Za-z0-9+.-]*://)([^/:?#]+)(.*)$"

  # records and the records of each group, by their origin
  inputs = merge(
    { records = var.records },
    { for group, g in var.record_groups : "group:${group}" => try(g.records, {}) },
  )

  # Every name and target of the input that may need converting
  names = try(distinct(compact(flatten([
    var.zone_name == null ? "" : var.zone_name,
    var.allowed_cname_conflicts,
    var.owned_names == null ? [] : concat(var.owned_names.include, var.owned_names.exclude),
    [
      for records in values(local.inputs) : [
        for name, types in records : [
          name,
          [
            for type, list in types : [
              for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
                length(split(".", type)) > 1 ? join(".", slice(split(".", type), 0, length(split(".", type)) - 1)) : "",
                [for record in list : try(tostring(record.content), "") if contains(local.name_content_kinds, kind)],
                [for record in list : try(tostring(record.data.target), "") if contains(["SRV", "HTTPS", "SVCB"], kind)],
                [for record in list : try(tostring(record.data.replacement), "") if kind == "NAPTR"],
                [for record in list : try(regex(local.uri, tostring(record.data.target))[1], "") if kind == "URI"],
              ]
            ]
          ],
        ]
      ]
    ],
  ]))), [])
  ascii = { for n in local.names : n => can(regex("[^[:ascii:]]", n)) ? provider::idna::to_ascii(n) : n }

  # One entry per name and type of each origin, with the records converted
  entries = try(flatten([
    for origin, records in local.inputs : [
      for name, types in records : [
        for type, list in types : [
          for kind in [element(split(".", type), length(split(".", type)) - 1)] : {
            origin = origin
            name   = local.ascii[name]
            type   = length(split(".", type)) > 1 ? "${local.ascii[join(".", slice(split(".", type), 0, length(split(".", type)) - 1))]}.${kind}" : type
            list = [
              for record in list : try(merge(
                record,
                contains(local.name_content_kinds, kind) && try(record.content, null) != null ? { content = local.ascii[tostring(record.content)] } : {},
                contains(["SRV", "HTTPS", "SVCB"], kind) && try(record.data.target, null) != null ? { data = merge(record.data, { target = local.ascii[tostring(record.data.target)] }) } : {},
                kind == "NAPTR" && try(record.data.replacement, null) != null ? { data = merge(record.data, { replacement = local.ascii[tostring(record.data.replacement)] }) } : {},
                kind == "URI" && can(regex(local.uri, tostring(record.data.target))) ? {
                  data = merge(record.data, { target = join("", [for i, part in regex(local.uri, tostring(record.data.target)) : i == 1 ? local.ascii[part] : part]) })
                } : {},
              ), record)
            ]
          }
        ]
      ]
    ]
  ]), null)

  # Names and type keys that differ only in their form ("bücher" and "xn--bcher-kva")
  # are joined, like the same name written twice; the v5 wrapper then finds duplicates
  converted = local.entries == null ? null : {
    for origin in keys(local.inputs) : origin => {
      for name in distinct([for e in local.entries : e.name if e.origin == origin]) : name => {
        for type in distinct([for e in local.entries : e.type if e.origin == origin && e.name == name]) : type => flatten([
          for e in local.entries : e.list if e.origin == origin && e.name == name && e.type == type
        ])
      }
    }
  }

  # try instead of a conditional: the converted value has other attribute names than the
  # input, so the two cannot be unified into one type
  records = try(local.converted["records"], var.records)
  record_groups = try({
    # A group without records stays as written, so the v5 wrapper reports it
    for group, g in var.record_groups : group => try(merge(g, { records = g.records == null ? {} : local.converted["group:${group}"] }), g)
  }, var.record_groups)

  # Cloudflare returns the name of an internationalized zone in Unicode, so the zone is
  # looked up here, with its name converted, instead of in the v5 wrapper
  zone_name = var.zone_name != null ? local.ascii[var.zone_name] : provider::idna::to_ascii(data.cloudflare_zone.this[0].name)
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
  allowed_cname_conflicts = [for n in var.allowed_cname_conflicts : local.ascii[n]]
  minimum_ttl             = var.minimum_ttl
  owned_names = var.owned_names == null ? null : {
    include = [for n in var.owned_names.include : local.ascii[n]]
    exclude = [for n in var.owned_names.exclude : local.ascii[n]]
  }
}
