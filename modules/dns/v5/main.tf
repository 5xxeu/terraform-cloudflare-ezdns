locals {
  root_domain = coalesce(var.zone_name, try(data.cloudflare_zone.this[0].name, null))

  # Fields of data that hold text (the other fields are numbers or N/S, E/W)
  text_data_fields = ["alpn", "certificate", "digest", "ech", "fingerprint", "ipv4hint", "ipv6hint", "mandatory", "public_key", "regex", "replacement", "service", "target", "value"]
}

# record_groups merged into records: lists of the same name and type are joined
# (records first, then the groups in the order of their names), and each grouped
# record gets the defaults of its group and its source for error messages. A record's
# own value wins over the group default; proxied applies to the types that can be
# proxied only
locals {
  # No try() over the records: try() returns an unknown result for a value that is not
  # wholly known, so one value computed by another resource would make every key
  # unknown. Malformed groups are reported by the validation of record_groups
  group_entries = flatten([
    for group, g in var.record_groups : [
      for records in [for x in [g] : lookup(x, "records", {}) if can(keys(x))] : [
        for name, types in records : [
          for type, list in types : [
            for index, record in list : {
              name = name
              type = type
              record = merge(record, {
                ttl     = try(record.ttl, null) != null ? record.ttl : try(g.defaults.ttl, null)
                proxied = try(record.proxied, null) != null ? record.proxied : contains(["A", "AAAA", "CNAME", "ALIASES"], element(split(".", type), length(split(".", type)) - 1)) ? try(g.defaults.proxied, null) : null
                comment = try(record.comment, null) != null ? record.comment : try(g.defaults.comment, null)
                tags    = length(concat(try([for tag in g.defaults.tags : tag], []), try([for tag in record.tags : tag], []))) > 0 ? concat(try([for tag in g.defaults.tags : tag], []), try([for tag in record.tags : tag], [])) : null
                source  = "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}]"
              })
            }
          ]
        ]
      ] if can(keys(records))
    ]
  ])

  # The entries of the groups by name, built once, so that merging them takes one
  # lookup per name instead of a pass over all entries (quadratic with many groups).
  # Names are known, so the keys stay known also with computed values; without groups
  # the lookups are empty
  group_names  = { for e in local.group_entries : e.name => e... }
  record_names = toset(keys(var.records))

  all_records = merge(
    {
      for name, types in var.records : name => merge(
        { for type, list in types : type => concat([for record in list : record], [for e in lookup(local.group_names, name, []) : e.record if e.type == type]) },
        { for type in distinct([for e in lookup(local.group_names, name, []) : e.type if !contains(keys(types), e.type)]) : type => [for e in lookup(local.group_names, name, []) : e.record if e.type == type] },
      )
    },
    {
      for name, entries in local.group_names : name => {
        for type in distinct([for e in entries : e.type]) : type => [for e in entries : e.record if e.type == type]
      } if !contains(local.record_names, name)
    },
  )
}

module "records" {
  source = "../records"

  root_domain             = local.root_domain
  records                 = local.all_records
  existing_records        = local.existing_records
  import_existing         = var.import_existing
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = var.minimum_ttl
  owned_names             = var.owned_names
  unmanaged_ignore        = var.unmanaged_ignore
}

data "cloudflare_zone" "this" {
  count   = var.zone_name == null ? 1 : 0
  zone_id = var.zone_id

  lifecycle {
    # Cloudflare returns the name of an internationalized zone in Unicode, while
    # record names come back in Punycode
    postcondition {
      condition     = !can(regex("[^[:ascii:]]", self.name))
      error_message = "The zone ${jsonencode(self.name)} has an internationalized name, which Cloudflare returns in Unicode: set zone_name in Punycode (xn--mnchen-3ya.de for münchen.de; provider::idna::to_ascii of the 5xxeu/idna provider converts it)."
    }
  }
}

resource "cloudflare_dns_record" "record" {
  for_each = module.records.flat_records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content

  ttl = each.value.proxied ? 1 : each.value.ttl

  # Records with structured data (CAA, SRV, ...) cannot be proxied
  proxied  = each.value.data == null ? each.value.proxied : null
  priority = each.value.priority
  comment  = each.value.comment
  tags     = length(each.value.tags) > 0 ? each.value.tags : null
  settings = each.value.settings

  # Numeric flags (CAA, DNSKEY) are sent as numbers, NAPTR flags as a string
  data = each.value.data == null ? null : {
    algorithm      = lookup(each.value.data, "algorithm", null)
    altitude       = lookup(each.value.data, "altitude", null)
    certificate    = lookup(each.value.data, "certificate", null)
    digest         = lookup(each.value.data, "digest", null)
    digest_type    = lookup(each.value.data, "digest_type", null)
    fingerprint    = lookup(each.value.data, "fingerprint", null)
    flags          = try(tonumber(each.value.data["flags"]), lookup(each.value.data, "flags", null))
    key_tag        = lookup(each.value.data, "key_tag", null)
    lat_degrees    = lookup(each.value.data, "lat_degrees", null)
    lat_direction  = lookup(each.value.data, "lat_direction", null)
    lat_minutes    = lookup(each.value.data, "lat_minutes", null)
    lat_seconds    = lookup(each.value.data, "lat_seconds", null)
    long_degrees   = lookup(each.value.data, "long_degrees", null)
    long_direction = lookup(each.value.data, "long_direction", null)
    long_minutes   = lookup(each.value.data, "long_minutes", null)
    long_seconds   = lookup(each.value.data, "long_seconds", null)
    matching_type  = lookup(each.value.data, "matching_type", null)
    order          = lookup(each.value.data, "order", null)
    port           = lookup(each.value.data, "port", null)
    precision_horz = lookup(each.value.data, "precision_horz", null)
    precision_vert = lookup(each.value.data, "precision_vert", null)
    preference     = lookup(each.value.data, "preference", null)
    priority       = lookup(each.value.data, "priority", null)
    protocol       = lookup(each.value.data, "protocol", null)
    public_key     = lookup(each.value.data, "public_key", null)
    regex          = lookup(each.value.data, "regex", null)
    replacement    = lookup(each.value.data, "replacement", null)
    selector       = lookup(each.value.data, "selector", null)
    service        = lookup(each.value.data, "service", null)
    size           = lookup(each.value.data, "size", null)
    tag            = lookup(each.value.data, "tag", null)
    target         = lookup(each.value.data, "target", null)
    type           = lookup(each.value.data, "type", null)
    usage          = lookup(each.value.data, "usage", null)
    value          = lookup(each.value.data, "value", null)
    weight         = lookup(each.value.data, "weight", null)
  }
}

# Numbers in text values are written in their canonical form ("0123" -> "123",
# "1.10" -> "1.1"), which loses what was written in YAML; quoting keeps it. The text
# fields of data are checked too (a hex digest of digits loses its leading zeros);
# numeric fields such as port or priority may be numbers. Grouped records are checked
# too (record_groups), with their source
check "records_text_values_are_strings" {
  assert {
    condition = alltrue(flatten([
      for name, types in local.all_records : [
        for type, list in types : [
          for record in list : concat(
            # fine: a JSON string, or a value that is not a number
            [for attribute in ["content", "key", "comment", "tag"] : try(record[attribute], null) == null || startswith(jsonencode(try(record[attribute], "")), "\"") || !can(tonumber(try(record[attribute], "")))],
            [for field in setintersection(try(keys(record.data), []), local.text_data_fields) : try(record.data[field], null) == null || startswith(jsonencode(try(record.data[field], "")), "\"") || !can(tonumber(try(record.data[field], "")))],
            # tags may be a list or a set (a set has no index), so the values are iterated
            try([for tag in record.tags : startswith(jsonencode(tag), "\"") || !can(tonumber(tag))], []),
          )
        ]
      ]
    ]))
    error_message = "Text values given as numbers are written in their canonical form (0123 -> 123, 1.10 -> 1.1); in YAML quote them to keep them as written:\n${join("\n", flatten([
      for name, types in local.all_records : [
        for type, list in types : [
          for index, record in list : concat(
            [
              for attribute in ["content", "key", "comment", "tag"] : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.${attribute} is ${jsonencode(record[attribute])}"
              if try(record[attribute], null) != null && !startswith(jsonencode(try(record[attribute], "")), "\"") && can(tonumber(try(record[attribute], "")))
            ],
            [
              for field in setintersection(try(keys(record.data), []), local.text_data_fields) : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.data.${field} is ${jsonencode(try(record.data[field], ""))}"
              if try(record.data[field], null) != null && !startswith(jsonencode(try(record.data[field], "")), "\"") && can(tonumber(try(record.data[field], "")))
            ],
            [
              for tag in try([for tag in record.tags : tag], []) : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.tags has ${jsonencode(tag)}"
              if !startswith(jsonencode(tag), "\"") && can(tonumber(tag))
            ],
          )
        ]
      ]
    ]))}"
  }
}


# Attributes that the module ignores for a record type (content of a record with data,
# priority other than MX and URI, CAA tag and flags on other types) are a mistake in the
# configuration: a warning in 2.x, an error from 3.0
locals {
  unused_attributes = flatten([
    for name, types in local.all_records : [
      for type, list in types : [
        for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
          for index, record in list : [
            for attribute, kinds in {
              content  = ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES"]
              priority = ["MX", "URI"]
              tag      = ["CAA"]
              flags    = ["CAA"]
            } : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.${attribute}"
            # a conditional, so a value known only after apply is not looked at where
            # the attribute applies
            if contains(kinds, kind) ? false : try(record[attribute], null) != null
          ]
          # unknown types fail in the records module
        ] if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
      ]
    ]
  ])
}

check "records_unused_attributes" {
  assert {
    condition     = length(local.unused_attributes) == 0
    error_message = "These attributes do not apply to the type of their record and are ignored (SRV keeps its priority in data; content is for records without data; tag and flags are for CAA). Remove them: from 3.0 they will fail the plan:\n${join("\n", local.unused_attributes)}"
  }
}
