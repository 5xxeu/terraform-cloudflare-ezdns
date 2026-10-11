locals {
  # Fields of data that hold text (the other fields are numbers or N/S, E/W)
  text_data_fields = ["alpn", "certificate", "digest", "ech", "fingerprint", "ipv4hint", "ipv6hint", "mandatory", "public_key", "regex", "replacement", "service", "target", "value"]
}

# record_groups merged into records: lists of the same name and type are joined
# (records first, then the groups in the order of their names), and each grouped
# record gets the defaults of its group and its source for error messages. A record's
# own value wins over the group default; proxied applies to the types that can be
# proxied only
locals {
  group_entries = flatten([
    for group, g in var.record_groups : [
      for name, types in try(g.records, {}) : [
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
    ]
  ])

  all_records = {
    for name in distinct(concat(keys(var.records), [for e in local.group_entries : e.name])) : name => {
      for type in distinct(concat(keys(try(var.records[name], {})), [for e in local.group_entries : e.type if e.name == name])) : type => concat(
        [for record in try(var.records[name][type], []) : record],
        [for e in local.group_entries : e.record if e.name == name && e.type == type],
      )
    }
  }
}

module "records" {
  source = "../records"

  root_domain             = var.zone_name
  records                 = local.all_records
  import_existing         = false
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = var.minimum_ttl
  owned_names             = var.owned_names
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
            [for field in setintersection(try(keys(record.data), []), local.text_data_fields) : startswith(jsonencode(try(record.data[field], "")), "\"") || !can(tonumber(try(record.data[field], "")))],
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
              if !startswith(jsonencode(try(record.data[field], "")), "\"") && can(tonumber(try(record.data[field], "")))
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
            if try(record[attribute], null) != null && !contains(kinds, kind)
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
