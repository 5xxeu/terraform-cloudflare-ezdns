# The preparation of records shared by the v5 wrapper and the compile module, before
# the records module converts them to its type: record_groups merged into records, and
# the checks that need the values as given (the types of the values are lost in the
# conversion). The inputs are checked by the module that calls this one (shapes and
# attribute names); here only the attributes that do not apply to their record type.

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
  # index per name instead of a pass over all entries (quadratic with many groups).
  # Every name of records is in record_group_entries, most with no entries: an index
  # costs the same for any number of names, while a function such as lookup() or
  # contains() reads its whole collection argument on every call. Names are known, so
  # the keys stay known also with computed values
  group_names          = { for e in local.group_entries : e.name => e... }
  record_group_entries = merge({ for name in keys(var.records) : name => [] }, local.group_names)

  # An empty list in place of the types of a name (app = []) is a name without records
  all_records = merge(
    {
      for name, types in var.records : name => merge(
        { for type, list in types : type => concat([for record in list : record], [for e in local.record_group_entries[name] : e.record if e.type == type]) },
        { for type in distinct([for e in local.record_group_entries[name] : e.type if !contains(try(keys(types), []), e.type)]) : type => [for e in local.record_group_entries[name] : e.record if e.type == type] },
      )
    },
    {
      for name in setsubtract(keys(local.group_names), keys(var.records)) : name => {
        for type in distinct([for e in local.group_names[name] : e.type]) : type => [for e in local.group_names[name] : e.record if e.type == type]
      }
    },
  )
}

# Numbers in text values are written in their canonical form ("0123" -> "123",
# "1.10" -> "1.1"), which loses what was written in YAML; quoting keeps it. The text
# fields of data are checked too (a hex digest of digits loses its leading zeros);
# numeric fields such as port or priority may be numbers. Grouped records are checked
# too (record_groups), with their source
check "records_text_values_are_strings" {
  assert {
    condition = alltrue([
      for name, types in local.all_records : alltrue([
        for type, list in types : alltrue([
          for record in list : alltrue(concat(
            # fine: a JSON string, or a value that is not a number
            [for attribute in ["content", "name", "key", "comment", "tag"] : try(record[attribute], null) == null || startswith(jsonencode(try(record[attribute], "")), "\"") || !can(tonumber(try(record[attribute], "")))],
            [for field in setintersection(try(keys(record.data), []), local.text_data_fields) : try(record.data[field], null) == null || startswith(jsonencode(try(record.data[field], "")), "\"") || !can(tonumber(try(record.data[field], "")))],
            # tags may be a list or a set (a set has no index), so the values are iterated
            try([for tag in record.tags : startswith(jsonencode(tag), "\"") || !can(tonumber(tag))], []),
          ))
        ])
      ])
    ])
    error_message = "Text values given as numbers are written in their canonical form (0123 -> 123, 1.10 -> 1.1); in YAML quote them to keep them as written:\n${join("\n", flatten([
      for name, types in local.all_records : [
        for type, list in types : [
          for index, record in list : concat(
            [
              for attribute in ["content", "name", "key", "comment", "tag"] : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.${attribute} is ${jsonencode(record[attribute])}"
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
