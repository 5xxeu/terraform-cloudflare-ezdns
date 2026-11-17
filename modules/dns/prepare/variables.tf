# Both inputs are passed on from the v5 wrapper or the compile module, which check their
# shapes and attribute names. Each validation here looks at its own input only, with
# try() around the expression: a malformed value is reported by the caller.

variable "records" {
  description = "The records input of the calling module, as given (records[NAME][TYPE] = [RECORD, ...])"
  # Not a typed object: the values are passed on as given, see main.tf
  type     = any
  default  = {}
  nullable = false

  # Attributes that the module would ignore for a record type (see local.attribute_kinds in
  # main.tf) are a mistake in the configuration. The condition is a conditional, so a value
  # known only after apply is not looked at where the attribute applies; elsewhere such a
  # value is checked at apply. The condition has to refer to var.records itself, so the list
  # cannot be a local (a local of var.records used here is a dependency cycle)
  validation {
    condition = try(alltrue([
      for name, types in var.records : alltrue([
        for type, list in types : alltrue([
          for kind in [element(split(".", type), length(split(".", type)) - 1)] : alltrue([
            for record in list : !(
              (contains(local.attribute_kinds.content, kind) ? false : try(record.content, null) != null)
              || (contains(local.attribute_kinds.name, kind) ? false : try(record.name, null) != null)
              || (contains(local.attribute_kinds.priority, kind) ? false : try(record.priority, null) != null)
              || (contains(local.attribute_kinds.tag, kind) ? false : try(record.tag, null) != null)
              || (contains(local.attribute_kinds.flags, kind) ? false : try(record.flags, null) != null)
            )
          ]) if contains(local.known_types, kind) # unknown types fail in the records module
        ])
      ])
    ]), true)
    error_message = "These attributes do not apply to the type of their record (SRV keeps its priority in data; content is for records without data; tag and flags are for CAA; name is for ALIASES, which have the name of the CNAME they create in name, not in content). Remove them:\n${try(join("\n", flatten([
      for name, types in var.records : [
        for type, list in types : [
          for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
            for index, record in list : [
              for attribute, kinds in local.attribute_kinds : "records[\"${name}\"][\"${type}\"][${index}].${attribute}"
              if contains(kinds, kind) ? false : try(record[attribute], null) != null
            ]
          ] if contains(local.known_types, kind)
        ]
      ]
    ])), "")}"
  }
}

variable "record_groups" {
  description = "The record_groups input of the calling module, as given (record_groups[GROUP] = { records = RECORDS, defaults = { ttl, proxied, comment, tags } })"
  type        = any
  default     = {}
  nullable    = false

  # Attributes that do not apply to the type of their record, as in records
  validation {
    condition = try(alltrue([
      for group, g in var.record_groups : alltrue([
        for records in [for x in [g] : lookup(x, "records", {}) if can(keys(x))] : alltrue([
          for name, types in records : alltrue([
            for type, list in types : alltrue([
              for kind in [element(split(".", type), length(split(".", type)) - 1)] : alltrue([
                for record in list : !(
                  (contains(local.attribute_kinds.content, kind) ? false : try(record.content, null) != null)
                  || (contains(local.attribute_kinds.name, kind) ? false : try(record.name, null) != null)
                  || (contains(local.attribute_kinds.priority, kind) ? false : try(record.priority, null) != null)
                  || (contains(local.attribute_kinds.tag, kind) ? false : try(record.tag, null) != null)
                  || (contains(local.attribute_kinds.flags, kind) ? false : try(record.flags, null) != null)
                )
              ]) if contains(local.known_types, kind)
            ])
          ])
        ]) if can(keys(records))
      ])
    ]), true)
    error_message = "These attributes do not apply to the type of their record (SRV keeps its priority in data; content is for records without data; tag and flags are for CAA; name is for ALIASES, which have the name of the CNAME they create in name, not in content). Remove them:\n${try(join("\n", flatten([
      for group, g in var.record_groups : [
        for records in [for x in [g] : lookup(x, "records", {}) if can(keys(x))] : [
          for name, types in records : [
            for type, list in types : [
              for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
                for index, record in list : [
                  for attribute, kinds in local.attribute_kinds : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}].${attribute}"
                  if contains(kinds, kind) ? false : try(record[attribute], null) != null
                ]
              ] if contains(local.known_types, kind)
            ]
          ]
        ] if can(keys(records))
      ]
    ])), "")}"
  }
}
