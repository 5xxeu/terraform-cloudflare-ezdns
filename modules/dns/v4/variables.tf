variable "zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "zone_name" {
  description = "Zone domain name (e.g. example.com). If null, it is looked up from zone_id. A trailing dot is ignored. Internationalized zones must set it, in Punycode"
  type        = string
  default     = null

  # Checked here: an empty name would otherwise fail in coalesce() with an unclear error.
  # A non-ASCII name gets its own error, since the DNS name rule does not say why it fails
  validation {
    condition     = var.zone_name == null || !can(regex("[^[:ascii:]]", var.zone_name))
    error_message = "zone_name must be in Punycode (xn--mnchen-3ya.de for münchen.de; provider::idna::to_ascii of the 5xxeu/idna provider converts it). An internationalized zone needs it set: Cloudflare returns the names of such zones in Unicode, so they cannot be looked up from zone_id."
  }

  validation {
    condition     = var.zone_name == null || can(regex("[^[:ascii:]]", var.zone_name)) || can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", var.zone_name))
    error_message = "zone_name must be the DNS name of the zone, such as example.com (or null to look it up from zone_id)."
  }
}

variable "records" {
  description = <<-EOT
    DNS records: `records[NAME][TYPE] = [RECORD, ...]`, where NAME is a name within the
    zone (`@` for the apex) and TYPE a record type, optionally with a prefix
    (`"_acme-challenge.TXT"`). Record attributes: `content`, `ttl`, `proxied`, `priority`,
    `tag`, `flags`, `data`, `key`, `comment`, `tags`, `settings` (`flatten_cname`,
    `ipv4_only`, `ipv6_only`) and `private_routing`. See the README for the details. Unknown attributes fail at plan.
  EOT
  # Not a typed object: Terraform silently drops unknown attributes when converting to an
  # object type, so misspelled attributes are checked here and the typed structure is
  # built by the records module
  type    = any
  default = {}
  # Left out it is {}; an explicit null (an emptied YAML file) is rejected below instead
  # of being taken as {}, which would delete every record

  validation {
    condition     = var.records != null
    error_message = "records is null, for example from an empty YAML file or a records: key without records. Pass {} (or leave records out) to manage no records in records; null is rejected so that an emptied file does not delete every record."
  }

  validation {
    condition = try(alltrue(flatten([
      for name, types in var.records : [
        for type, list in types : [
          for record in list : (
            can(keys(record))
            && length(setsubtract(keys(record), ["content", "ttl", "proxied", "priority", "tag", "flags", "data", "key", "comment", "tags", "settings", "private_routing"])) == 0
            && (try(record.settings, null) == null || length(setsubtract(try(keys(record.settings), ["?"]), ["flatten_cname", "ipv4_only", "ipv6_only"])) == 0)
          )
        ]
      ]
    ])), false)
    error_message = try(
      "Invalid records (allowed attributes: content, ttl, proxied, priority, tag, flags, data, key, comment, tags, settings, private_routing):\n${join("\n", flatten([
        for name, types in var.records : [
          for type, list in types : [
            for index, record in list : concat(
              can(keys(record)) ? [] : ["records[\"${name}\"][\"${type}\"][${index}] must be an object"],
              [for attribute in setsubtract(try(keys(record), []), ["content", "ttl", "proxied", "priority", "tag", "flags", "data", "key", "comment", "tags", "settings", "private_routing"]) : "records[\"${name}\"][\"${type}\"][${index}]: unknown attribute \"${attribute}\""],
              [for attribute in setsubtract(try(keys(record.settings), []), ["flatten_cname", "ipv4_only", "ipv6_only"]) : "records[\"${name}\"][\"${type}\"][${index}].settings: unknown attribute \"${attribute}\""]
            )
          ]
        ]
      ]))}",
      "records must be a map of names to maps of record types to lists of records."
    )
  }
  # YAML 1.1 reads unquoted off/on/yes/no/N/Y as booleans, and Terraform would turn them
  # into "false"/"true" without an error; values that must be text cannot be booleans.
  # An unquoted N is accepted as a LOC lat_direction, where it can only mean north
  validation {
    condition = try(alltrue(flatten([
      for name, types in var.records : [
        for type, list in types : [
          for record in list : concat(
            [for attribute in ["content", "key", "comment", "tag"] : !contains(["true", "false"], jsonencode(try(record[attribute], "")))],
            [for field in try(keys(record.data), []) : !contains(["true", "false"], jsonencode(try(record.data[field], ""))) || (field == "lat_direction" && jsonencode(try(record.data[field], "")) == "false")],
            # tags may be a list or a set (a set has no index), so the values are iterated
            try([for tag in record.tags : !contains(["true", "false"], jsonencode(tag))], []),
          )
        ]
      ]
    ])), true)
    error_message = try(
      "Text values must be strings, in YAML quote them (\"off\", \"yes\", \"N\"); unquoted they are read as booleans:\n${join("\n", flatten([
        for name, types in var.records : [
          for type, list in types : [
            for index, record in list : concat(
              [
                for attribute in ["content", "key", "comment", "tag"] : "records[\"${name}\"][\"${type}\"][${index}].${attribute} is ${jsonencode(record[attribute])}"
                if contains(["true", "false"], jsonencode(try(record[attribute], "")))
              ],
              [
                for field in try(keys(record.data), []) : "records[\"${name}\"][\"${type}\"][${index}].data.${field} is ${jsonencode(try(record.data[field], ""))}"
                if contains(["true", "false"], jsonencode(try(record.data[field], ""))) && !(field == "lat_direction" && jsonencode(try(record.data[field], "")) == "false")
              ],
              [
                for tag in try([for tag in record.tags : tag], []) : "records[\"${name}\"][\"${type}\"][${index}].tags has ${jsonencode(tag)}"
                if contains(["true", "false"], jsonencode(tag))
              ],
            )
          ]
        ]
      ]))}",
      "Text values must be strings."
    )
  }
}

variable "record_groups" {
  description = <<-EOT
    Further records in named groups, each with defaults of its own:
    `record_groups[GROUP] = { records = RECORDS, defaults = { ttl, proxied, comment, tags } }`,
    where RECORDS has the form of `records` (e.g. one YAML file per group). The groups and
    `records` are merged by name and type: the lists of records are joined, and a record
    defined twice fails as a duplicate. A record's own value wins over the group default,
    which wins over the module default (`proxied` applies to A, AAAA, CNAME and ALIASES
    only; group tags are added to `default_tags` and the record's tags). The group name
    is not a part of the record keys, so moving a record between groups or into
    `records` keeps it in the state.
  EOT
  # Not a typed object, like records: unknown attributes are checked here
  type    = any
  default = {}
  # Left out it is {}; an explicit null (an emptied YAML file) is rejected below instead
  # of being taken as {}, which would delete every record

  validation {
    condition     = var.record_groups != null
    error_message = "record_groups is null, for example from a YAML file that decodes to nothing. Pass {} (or leave record_groups out) for no groups; null is rejected so that an emptied file does not delete the records of every group."
  }

  validation {
    condition = try(alltrue(flatten([
      for group, g in var.record_groups : concat(
        [
          can(keys(g)) && length(setsubtract(keys(g), ["defaults", "records"])) == 0 && can(keys(g.records)),
          # Terraform 1.8 evaluates both sides of ||, so g.defaults is read with try
          try(g.defaults, null) == null || (
            can(keys(g.defaults)) && length(setsubtract(try(keys(g.defaults), []), ["ttl", "proxied", "comment", "tags"])) == 0
            && (try(g.defaults.ttl, null) == null || can(tonumber(g.defaults.ttl)) && !startswith(jsonencode(try(g.defaults.ttl, 0)), "\""))
            && (try(g.defaults.proxied, null) == null || contains(["true", "false"], jsonencode(try(g.defaults.proxied, false))))
            && (try(g.defaults.comment, null) == null || startswith(jsonencode(try(g.defaults.comment, "")), "\""))
            && (try(g.defaults.tags, null) == null || alltrue([for tag in try([for tag in g.defaults.tags : tag], [0]) : startswith(jsonencode(tag), "\"")]))
          ),
        ],
        [
          for name, types in try(g.records, {}) : [
            for type, list in types : [
              for record in list : (
                can(keys(record))
                && length(setsubtract(keys(record), ["content", "ttl", "proxied", "priority", "tag", "flags", "data", "key", "comment", "tags", "settings", "private_routing"])) == 0
                && (try(record.settings, null) == null || length(setsubtract(try(keys(record.settings), ["?"]), ["flatten_cname", "ipv4_only", "ipv6_only"])) == 0)
              )
            ]
          ]
        ],
      )
    ])), false)
    error_message = try(
      "Invalid record_groups (a group has records and optionally defaults with ttl, proxied, comment and tags; allowed record attributes: content, ttl, proxied, priority, tag, flags, data, key, comment, tags, settings, private_routing):\n${join("\n", flatten([
        for group, g in var.record_groups : concat(
          can(keys(g)) ? [] : ["record_groups[\"${group}\"] must be an object with records and optionally defaults"],
          [for attribute in setsubtract(try(keys(g), []), ["defaults", "records"]) : "record_groups[\"${group}\"]: unknown attribute \"${attribute}\""],
          can(keys(g)) && !can(keys(g.records)) ? ["record_groups[\"${group}\"].records must be a map of names to maps of record types to lists of records"] : [],
          [for attribute in setsubtract(try(keys(g.defaults), []), ["ttl", "proxied", "comment", "tags"]) : "record_groups[\"${group}\"].defaults: unknown attribute \"${attribute}\""],
          try(g.defaults.ttl, null) == null || can(tonumber(g.defaults.ttl)) && !startswith(jsonencode(try(g.defaults.ttl, 0)), "\"") ? [] : ["record_groups[\"${group}\"].defaults.ttl must be a number"],
          try(g.defaults.proxied, null) == null || contains(["true", "false"], jsonencode(try(g.defaults.proxied, false))) ? [] : ["record_groups[\"${group}\"].defaults.proxied must be true or false"],
          try(g.defaults.comment, null) == null || startswith(jsonencode(try(g.defaults.comment, "")), "\"") ? [] : ["record_groups[\"${group}\"].defaults.comment must be a string"],
          try(g.defaults.tags, null) == null || alltrue([for tag in try([for tag in g.defaults.tags : tag], [0]) : startswith(jsonencode(tag), "\"")]) ? [] : ["record_groups[\"${group}\"].defaults.tags must be a list of strings"],
          flatten([
            for name, types in try(g.records, {}) : [
              for type, list in types : [
                for index, record in list : concat(
                  can(keys(record)) ? [] : ["record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}] must be an object"],
                  [for attribute in setsubtract(try(keys(record), []), ["content", "ttl", "proxied", "priority", "tag", "flags", "data", "key", "comment", "tags", "settings", "private_routing"]) : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}]: unknown attribute \"${attribute}\""],
                  [for attribute in setsubtract(try(keys(record.settings), []), ["flatten_cname", "ipv4_only", "ipv6_only"]) : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}].settings: unknown attribute \"${attribute}\""]
                )
              ]
            ]
          ]),
        )
      ]))}",
      "record_groups must be a map of group names to objects with records (in the form of the records input) and optionally defaults."
    )
  }

  # Text values of grouped records cannot be booleans either (see records)
  validation {
    condition = try(alltrue(flatten([
      for group, g in var.record_groups : [
        for name, types in try(g.records, {}) : [
          for type, list in types : [
            for record in list : concat(
              [for attribute in ["content", "key", "comment", "tag"] : !contains(["true", "false"], jsonencode(try(record[attribute], "")))],
              [for field in try(keys(record.data), []) : !contains(["true", "false"], jsonencode(try(record.data[field], ""))) || (field == "lat_direction" && jsonencode(try(record.data[field], "")) == "false")],
              try([for tag in record.tags : !contains(["true", "false"], jsonencode(tag))], []),
            )
          ]
        ]
      ]
    ])), true)
    error_message = try(
      "Text values must be strings, in YAML quote them (\"off\", \"yes\", \"N\"); unquoted they are read as booleans:\n${join("\n", flatten([
        for group, g in var.record_groups : [
          for name, types in try(g.records, {}) : [
            for type, list in types : [
              for index, record in list : concat(
                [
                  for attribute in ["content", "key", "comment", "tag"] : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}].${attribute} is ${jsonencode(record[attribute])}"
                  if contains(["true", "false"], jsonencode(try(record[attribute], "")))
                ],
                [
                  for field in try(keys(record.data), []) : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}].data.${field} is ${jsonencode(try(record.data[field], ""))}"
                  if contains(["true", "false"], jsonencode(try(record.data[field], ""))) && !(field == "lat_direction" && jsonencode(try(record.data[field], "")) == "false")
                ],
                [
                  for tag in try([for tag in record.tags : tag], []) : "record_groups[\"${group}\"].records[\"${name}\"][\"${type}\"][${index}].tags has ${jsonencode(tag)}"
                  if contains(["true", "false"], jsonencode(tag))
                ],
              )
            ]
          ]
        ]
      ]))}",
      "Text values must be strings."
    )
  }
}

variable "default_ttl" {
  description = "TTL of records that do not set one (1 means automatic)"
  type        = number
  default     = 3600
  nullable    = false

  validation {
    condition     = floor(var.default_ttl) == var.default_ttl && (var.default_ttl == 1 || (var.default_ttl >= 30 && var.default_ttl <= 86400))
    error_message = "default_ttl must be a whole number of seconds, 1 (automatic) or between 30 and 86400."
  }
}

variable "default_proxied" {
  description = "Whether A, AAAA, CNAME and ALIASES records that do not set proxied are proxied by Cloudflare"
  type        = bool
  default     = false
  nullable    = false
}

variable "default_comment" {
  description = "Comment of records that do not set one, e.g. \"Managed by Terraform\""
  type        = string
  default     = null
}

variable "default_tags" {
  description = "Tags added to all records, e.g. [\"managed-by:terraform\"] (tags require a Cloudflare plan that supports them)"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_cname_conflicts" {
  description = "Names where a CNAME already shares its name with other records in the zone, e.g. [\"community\", \"*.legacy.example.com\"]. Cloudflare accepts this for records that are not proxied, and older zones often have such names; only the listed names are exempt from the CNAME check. Compared fully qualified and case-insensitively; a second CNAME on a name still fails, and listed names without a conflict show a warning"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "owned_names" {
  description = "The part of the zone that this module call manages: names in include and below them, except names in exclude and below them (e.g. include = [\"apps\"], exclude = [\"k8s.apps\"]). Configured records outside it fail at plan, and only existing records inside it are reported as unmanaged. Names like in records, compared fully qualified and case-insensitively, by whole labels (\"apps\" covers \"x.apps\", not \"myapps\"). null: the whole zone"
  type = object({
    include = optional(list(string), ["@"])
    exclude = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.owned_names == null || length(try(var.owned_names.include, [])) > 0 && length([for n in concat(try(var.owned_names.include, []), try(var.owned_names.exclude, [])) : n if !(n == "@" || can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", n)))]) == 0
    error_message = "owned_names must include at least one name, and list names like in records, without wildcards (\"@\", \"apps\", \"apps.example.com\"):\n${join("\n", [for n in concat(try(var.owned_names.include, []), try(var.owned_names.exclude, [])) : jsonencode(n) if !(n == "@" || can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", n)))])}"
  }
}

variable "minimum_ttl" {
  description = "Lowest TTL other than 1 (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones: set 30 there, keep 60 otherwise, or \"auto\" to take it from the plan of the zone (one more API call, which needs Zone Read; the compile module, which reads nothing, takes 30)"
  type        = string
  default     = "60"
  nullable    = false

  validation {
    condition     = contains(["30", "60", "auto"], var.minimum_ttl)
    error_message = "minimum_ttl must be 60, 30 for zones on the Cloudflare Enterprise plan, or \"auto\" to take it from the plan of the zone."
  }
}
