# Both inputs are passed on from the v5 wrapper or the compile module, which check their
# shapes and attribute names. Each validation here looks at its own input only, with
# try() around the expression: a malformed value is reported by the caller.

variable "records" {
  description = "The records input of the calling module, as given (records[NAME][TYPE] = [RECORD, ...])"
  # Not a typed object: the values are passed on as given, see main.tf
  type     = any
  default  = {}
  nullable = false

  # Attributes that the module would ignore for a record type (content of a record with
  # data, priority other than MX and URI, CAA tag and flags on other types) are a mistake
  # in the configuration. A conditional, so a value known only after apply is not looked
  # at where the attribute applies; elsewhere such a value is checked at apply
  validation {
    condition = try(alltrue([
      for name, types in var.records : alltrue([
        for type, list in types : alltrue([
          for kind in [element(split(".", type), length(split(".", type)) - 1)] : alltrue([
            for record in list : !(
              (contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind) ? try(record.content, null) != null : false)
              || (kind == "MX" || kind == "URI" ? false : try(record.priority, null) != null)
              || (kind == "CAA" ? false : try(record.tag, null) != null || try(record.flags, null) != null)
              || (kind == "ALIASES" ? try(record.content, null) != null : try(record.name, null) != null)
            )
            # unknown types fail in the records module
          ]) if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
        ])
      ])
    ]), true)
    # Terraform evaluates the message also when the condition holds, and both results of a
    # conditional: the list is built in a for expression whose if leaves it out then
    error_message = "These attributes do not apply to the type of their record (SRV keeps its priority in data; content is for records without data; tag and flags are for CAA; name is for ALIASES, which have the name of the CNAME they create in name, not in content). Remove them:\n${join("", [
      for ok in [try(alltrue([
        for name, types in var.records : alltrue([
          for type, list in types : alltrue([
            for kind in [element(split(".", type), length(split(".", type)) - 1)] : alltrue([
              for record in list : !(
                (contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind) ? try(record.content, null) != null : false)
                || (kind == "MX" || kind == "URI" ? false : try(record.priority, null) != null)
                || (kind == "CAA" ? false : try(record.tag, null) != null || try(record.flags, null) != null)
                || (kind == "ALIASES" ? try(record.content, null) != null : try(record.name, null) != null)
              )
            ]) if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
          ])
        ])
        ]), true)] : try(join("\n", flatten([
        for name, types in var.records : [
          for type, list in types : [
            for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
              for index, record in list : [
                for attribute, kinds in {
                  content  = ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA"]
                  name     = ["ALIASES"]
                  priority = ["MX", "URI"]
                  tag      = ["CAA"]
                  flags    = ["CAA"]
                } : "records[\"${name}\"][\"${type}\"][${index}].${attribute}"
                if contains(kinds, kind) ? false : try(record[attribute], null) != null
              ]
            ] if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
          ]
        ]
      ])), "") if !ok
    ])}"
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
                  (contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind) ? try(record.content, null) != null : false)
                  || (kind == "MX" || kind == "URI" ? false : try(record.priority, null) != null)
                  || (kind == "CAA" ? false : try(record.tag, null) != null || try(record.flags, null) != null)
                  || (kind == "ALIASES" ? try(record.content, null) != null : try(record.name, null) != null)
                )
                # unknown types fail in the records module
              ]) if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
            ])
          ])
        ]) if can(keys(records))
      ])
    ]), true)
    # Terraform evaluates the message also when the condition holds, and both results of a
    # conditional: the list is built in a for expression whose if leaves it out then
    error_message = "These attributes do not apply to the type of their record (SRV keeps its priority in data; content is for records without data; tag and flags are for CAA; name is for ALIASES, which have the name of the CNAME they create in name, not in content). Remove them:\n${join("", [
      for ok in [try(alltrue([
        for group, g in var.record_groups : alltrue([
          for records in [for x in [g] : lookup(x, "records", {}) if can(keys(x))] : alltrue([
            for name, types in records : alltrue([
              for type, list in types : alltrue([
                for kind in [element(split(".", type), length(split(".", type)) - 1)] : alltrue([
                  for record in list : !(
                    (contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind) ? try(record.content, null) != null : false)
                    || (kind == "MX" || kind == "URI" ? false : try(record.priority, null) != null)
                    || (kind == "CAA" ? false : try(record.tag, null) != null || try(record.flags, null) != null)
                    || (kind == "ALIASES" ? try(record.content, null) != null : try(record.name, null) != null)
                  )
                ]) if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
              ])
            ])
          ]) if can(keys(records))
        ])
        ]), true)] : try(join("\n", flatten([
        for group, g in var.record_groups : [
          for records in [for x in [g] : lookup(x, "records", {}) if can(keys(x))] : [
            for name, types in records : [
              for type, list in types : [
                for kind in [element(split(".", type), length(split(".", type)) - 1)] : [
                  for index, record in list : [
                    for attribute, kinds in {
                      content  = ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA"]
                      name     = ["ALIASES"]
                      priority = ["MX", "URI"]
                      tag      = ["CAA"]
                      flags    = ["CAA"]
                    } : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}].${attribute}"
                    if contains(kinds, kind) ? false : try(record[attribute], null) != null
                  ]
                ] if contains(["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
              ]
            ] if can(keys(records))
          ]
        ]
      ])), "") if !ok
    ])}"
  }
}
