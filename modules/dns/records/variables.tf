variable "root_domain" {
  description = "Zone domain name (e.g. example.com), used as the target suffix for aliases. A trailing dot is ignored"
  type        = string

  # Cloudflare returns the name of an internationalized zone in Unicode (münchen.de),
  # while record names come back in Punycode; such zones need zone_name in Punycode
  validation {
    condition     = !can(regex("[^[:ascii:]]", var.root_domain))
    error_message = "The zone name ${jsonencode(var.root_domain)} is not in Punycode: Cloudflare returns the names of internationalized zones in Unicode, so set zone_name in Punycode (xn--mnchen-3ya.de for münchen.de; provider::idna::to_ascii of the 5xxeu/idna provider converts it)."
  }

  validation {
    condition     = can(regex("[^[:ascii:]]", var.root_domain)) || can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", var.root_domain))
    error_message = "The zone name must be a DNS name such as example.com, got ${jsonencode(var.root_domain)}."
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

variable "minimum_ttl" {
  description = "Lowest TTL other than 1 (automatic): 60 seconds on every Cloudflare plan, 30 only on Enterprise zones"
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = contains([30, 60], var.minimum_ttl)
    error_message = "minimum_ttl must be 60, or 30 for zones on the Cloudflare Enterprise plan."
  }
}

variable "allowed_cname_conflicts" {
  description = "Names where a CNAME may share its name with other records, for existing zones that have such names (Cloudflare accepts them for records that are not proxied). Compared fully qualified and case-insensitively; a second CNAME on a name still fails"
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length([for n in var.allowed_cname_conflicts : n if !(n == "@" || can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", n)))]) == 0
    error_message = "allowed_cname_conflicts must list names like in records (\"@\", \"www\", \"www.example.com\", \"*.legacy\"):\n${join("\n", [for n in var.allowed_cname_conflicts : jsonencode(n) if !(n == "@" || can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", n)))])}"
  }
}

variable "records" {
  description = "DNS records grouped by base name (subdomain or @ for apex), then by record type"
  type = map(
    map(
      list(
        object({
          content  = optional(string)
          ttl      = optional(number) # default_ttl when not set
          proxied  = optional(bool)   # default_proxied when not set
          priority = optional(number)

          # for CAA
          tag   = optional(string)
          flags = optional(number, 0)

          # Structured data for SRV, URI, HTTPS, SVCB, TLSA, SMIMEA, SSHFP, DS, DNSKEY, CERT, NAPTR and LOC
          data = optional(map(string))

          # Stable key instead of the record value, so changing the value updates the record in place
          key = optional(string)

          # Where the record is defined, for error messages; set by the wrappers for
          # records of record_groups, not an input of its own (null: records[...])
          source = optional(string)

          # Shown in the Cloudflare dashboard: comment replaces default_comment, tags are added to default_tags
          comment = optional(string)
          tags    = optional(list(string))

          # Record settings (Cloudflare provider v5)
          settings = optional(object({
            flatten_cname = optional(bool)
            ipv4_only     = optional(bool)
            ipv6_only     = optional(bool)
          }))
        })
      )
    )
  )

  # Every validation lists the records that fail it as records["<name>"]["<type>"][<index>].
  # Validations cannot use locals on Terraform 1.8, so the record type is bound with
  # `for kind in [...]`, and the list of failures is written twice: in the condition and in
  # the error message
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : "records[\"${base_name}\"][\"${raw_key}\"]"
          if !contains(
            ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"],
            kind
          )
        ]
      ]
    ])) == 0
    error_message = "Unsupported record type. Supported: A, AAAA, CNAME, MX, NS, PTR, TXT, OPENPGPKEY, CAA, ALIASES, CERT, DNSKEY, DS, HTTPS, LOC, NAPTR, SMIMEA, SRV, SSHFP, SVCB, TLSA and URI (optionally with a prefix, e.g. \"_acme-challenge.TXT\"):\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : "records[\"${base_name}\"][\"${raw_key}\"]"
          if !contains(
            ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "TXT", "OPENPGPKEY", "CAA", "ALIASES", "CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"],
            kind
          )
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if rec.content == null || rec.content == ""
          ] if !contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
        ]
      ]
    ])) == 0
    error_message = "Every record except SRV, URI, HTTPS, SVCB, TLSA, SMIMEA, SSHFP, DS, DNSKEY, CERT, NAPTR and LOC must have a non-empty content:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if rec.content == null || rec.content == ""
          ] if !contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind) ? rec.data == null || length(coalesce(rec.data, {})) == 0 : rec.data != null
          ]
        ]
      ]
    ])) == 0
    error_message = "SRV, URI, HTTPS, SVCB, TLSA, SMIMEA, SSHFP, DS, DNSKEY, CERT, NAPTR and LOC records require data; other record types must not set it:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind) ? rec.data == null || length(coalesce(rec.data, {})) == 0 : rec.data != null
          ]
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : concat(
              [for field in setsubtract(keys(coalesce(rec.data, {})), lookup({
                SRV    = ["priority", "weight", "port", "target"]
                URI    = ["weight", "target"]
                HTTPS  = ["priority", "target", "value", "mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"]
                SVCB   = ["priority", "target", "value", "mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"]
                TLSA   = ["usage", "selector", "matching_type", "certificate"]
                SMIMEA = ["usage", "selector", "matching_type", "certificate"]
                SSHFP  = ["algorithm", "type", "fingerprint"]
                DS     = ["key_tag", "algorithm", "digest_type", "digest"]
                DNSKEY = ["flags", "protocol", "algorithm", "public_key"]
                CERT   = ["type", "key_tag", "algorithm", "certificate"]
                NAPTR  = ["order", "preference", "flags", "service", "regex", "replacement"]
                LOC = [
                  "lat_degrees", "lat_minutes", "lat_seconds", "lat_direction",
                  "long_degrees", "long_minutes", "long_seconds", "long_direction",
                  "altitude", "size", "precision_horz", "precision_vert",
                ]
              }, kind, [])) : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data: unknown field \"${field}\""],
              [for field in setsubtract(lookup({
                SRV    = ["priority", "weight", "port", "target"]
                URI    = ["weight", "target"]
                HTTPS  = ["priority", "target"]
                SVCB   = ["priority", "target"]
                TLSA   = ["usage", "selector", "matching_type", "certificate"]
                SMIMEA = ["usage", "selector", "matching_type", "certificate"]
                SSHFP  = ["algorithm", "type", "fingerprint"]
                DS     = ["key_tag", "algorithm", "digest_type", "digest"]
                DNSKEY = ["flags", "protocol", "algorithm", "public_key"]
                CERT   = ["type", "key_tag", "algorithm", "certificate"]
                NAPTR  = ["order", "preference", "replacement"]
                LOC = [
                  "lat_degrees", "lat_minutes", "lat_seconds", "lat_direction",
                  "long_degrees", "long_minutes", "long_seconds", "long_direction",
                ]
              }, kind, []), keys(coalesce(rec.data, {}))) : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data: missing field \"${field}\""],
            )
          ] if contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
        ]
      ]
    ])) == 0
    error_message = "Record data has unknown or missing fields. See \"Record Types\" in the README for the fields of each type:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : concat(
              [for field in setsubtract(keys(coalesce(rec.data, {})), lookup({
                SRV    = ["priority", "weight", "port", "target"]
                URI    = ["weight", "target"]
                HTTPS  = ["priority", "target", "value", "mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"]
                SVCB   = ["priority", "target", "value", "mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"]
                TLSA   = ["usage", "selector", "matching_type", "certificate"]
                SMIMEA = ["usage", "selector", "matching_type", "certificate"]
                SSHFP  = ["algorithm", "type", "fingerprint"]
                DS     = ["key_tag", "algorithm", "digest_type", "digest"]
                DNSKEY = ["flags", "protocol", "algorithm", "public_key"]
                CERT   = ["type", "key_tag", "algorithm", "certificate"]
                NAPTR  = ["order", "preference", "flags", "service", "regex", "replacement"]
                LOC = [
                  "lat_degrees", "lat_minutes", "lat_seconds", "lat_direction",
                  "long_degrees", "long_minutes", "long_seconds", "long_direction",
                  "altitude", "size", "precision_horz", "precision_vert",
                ]
              }, kind, [])) : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data: unknown field \"${field}\""],
              [for field in setsubtract(lookup({
                SRV    = ["priority", "weight", "port", "target"]
                URI    = ["weight", "target"]
                HTTPS  = ["priority", "target"]
                SVCB   = ["priority", "target"]
                TLSA   = ["usage", "selector", "matching_type", "certificate"]
                SMIMEA = ["usage", "selector", "matching_type", "certificate"]
                SSHFP  = ["algorithm", "type", "fingerprint"]
                DS     = ["key_tag", "algorithm", "digest_type", "digest"]
                DNSKEY = ["flags", "protocol", "algorithm", "public_key"]
                CERT   = ["type", "key_tag", "algorithm", "certificate"]
                NAPTR  = ["order", "preference", "replacement"]
                LOC = [
                  "lat_degrees", "lat_minutes", "lat_seconds", "lat_direction",
                  "long_degrees", "long_minutes", "long_seconds", "long_direction",
                ]
              }, kind, []), keys(coalesce(rec.data, {}))) : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data: missing field \"${field}\""],
            )
          ] if contains(["CERT", "DNSKEY", "DS", "HTTPS", "LOC", "NAPTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "URI"], kind)
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: ttl ${rec.ttl}"
            if !(rec.ttl == null || (floor(coalesce(rec.ttl, 1)) == coalesce(rec.ttl, 1) && (rec.ttl == 1 || (coalesce(rec.ttl, 1) >= 30 && coalesce(rec.ttl, 1) <= 86400))))
          ]
        ]
      ]
    ])) == 0
    error_message = "TTL must be a whole number of seconds, 1 (automatic) or between 30 and 86400:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: ttl ${rec.ttl}"
            if !(rec.ttl == null || (floor(coalesce(rec.ttl, 1)) == coalesce(rec.ttl, 1) && (rec.ttl == 1 || (coalesce(rec.ttl, 1) >= 30 && coalesce(rec.ttl, 1) <= 86400))))
          ]
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if coalesce(rec.proxied, false) && !contains(["A", "AAAA", "CNAME", "ALIASES"], kind)
          ]
        ]
      ]
    ])) == 0
    error_message = "Only A, AAAA, CNAME and ALIASES records can be proxied:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if coalesce(rec.proxied, false) && !contains(["A", "AAAA", "CNAME", "ALIASES"], kind)
          ]
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if rec.priority == null
          ] if contains(["MX", "URI"], kind)
        ]
      ]
    ])) == 0
    error_message = "MX and URI records require a priority:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if rec.priority == null
          ] if contains(["MX", "URI"], kind)
        ]
      ]
    ]))}"
  }

  # Priorities are 16-bit numbers in DNS
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: priority ${rec.priority}"
          if !(rec.priority == null || (floor(coalesce(rec.priority, 0)) == coalesce(rec.priority, 0) && coalesce(rec.priority, 0) >= 0 && coalesce(rec.priority, 0) <= 65535))
        ]
      ]
    ])) == 0
    error_message = "priority must be a whole number between 0 and 65535:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: priority ${rec.priority}"
          if !(rec.priority == null || (floor(coalesce(rec.priority, 0)) == coalesce(rec.priority, 0) && coalesce(rec.priority, 0) >= 0 && coalesce(rec.priority, 0) <= 65535))
        ]
      ]
    ]))}"
  }

  # Numeric fields of data have the ranges of their DNS wire format (LOC as in RFC 1876),
  # so a value out of range fails at plan instead of in the API. data is a map of
  # strings: a value that is not a number fails too. lat_direction "false" is an
  # unquoted N in YAML 1.1 (see keys.tf)
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : concat(
              [
                for field, range in lookup({
                  SRV    = { priority = [0, 65535, true], weight = [0, 65535, true], port = [0, 65535, true] }
                  URI    = { weight = [0, 65535, true] }
                  HTTPS  = { priority = [0, 65535, true], port = [0, 65535, true] }
                  SVCB   = { priority = [0, 65535, true], port = [0, 65535, true] }
                  TLSA   = { usage = [0, 255, true], selector = [0, 255, true], matching_type = [0, 255, true] }
                  SMIMEA = { usage = [0, 255, true], selector = [0, 255, true], matching_type = [0, 255, true] }
                  SSHFP  = { algorithm = [0, 255, true], type = [0, 255, true] }
                  DS     = { key_tag = [0, 65535, true], algorithm = [0, 255, true], digest_type = [0, 255, true] }
                  DNSKEY = { flags = [0, 65535, true], protocol = [0, 255, true], algorithm = [0, 255, true] }
                  CERT   = { type = [0, 65535, true], key_tag = [0, 65535, true], algorithm = [0, 255, true] }
                  NAPTR  = { order = [0, 65535, true], preference = [0, 65535, true] }
                  LOC = {
                    lat_degrees    = [0, 90, true], lat_minutes = [0, 59, true], lat_seconds = [0, 59.999, false],
                    long_degrees   = [0, 180, true], long_minutes = [0, 59, true], long_seconds = [0, 59.999, false],
                    altitude       = [-100000, 42849672.95, false], size = [0, 90000000, false],
                    precision_horz = [0, 90000000, false], precision_vert = [0, 90000000, false],
                  }
                  }, kind, {}) : [
                  for value in [lookup(coalesce(rec.data, {}), field, null)] : [
                    for n in [try(tonumber(value), null)] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(value)} (${range[2] ? "a whole number" : "a number"} from ${range[0]} to ${range[1]})"
                    if value != null && (n == null ? true : !(n >= range[0] && n <= range[1] && (range[2] ? floor(n) == n : true)))
                  ]
                ]
              ],
              [
                for field, allowed in lookup({ LOC = { lat_direction = ["N", "S", "false"], long_direction = ["E", "W"] } }, kind, {}) : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(lookup(coalesce(rec.data, {}), field, null))} (${join(" or ", [for a in allowed : a if a != "false"])})"
                if lookup(coalesce(rec.data, {}), field, null) != null && !contains(allowed, lookup(coalesce(rec.data, {}), field, ""))
              ],
              [
                for flags in [rec.flags] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.flags: ${flags} (a whole number from 0 to 255)"
                if kind == "CAA" && !(flags == null || (floor(coalesce(flags, 0)) == coalesce(flags, 0) && coalesce(flags, 0) >= 0 && coalesce(flags, 0) <= 255))
              ],
            )
          ]
        ]
      ]
    ])) == 0
    error_message = "Record data fields and CAA flags must be in range:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : concat(
              [
                for field, range in lookup({
                  SRV    = { priority = [0, 65535, true], weight = [0, 65535, true], port = [0, 65535, true] }
                  URI    = { weight = [0, 65535, true] }
                  HTTPS  = { priority = [0, 65535, true], port = [0, 65535, true] }
                  SVCB   = { priority = [0, 65535, true], port = [0, 65535, true] }
                  TLSA   = { usage = [0, 255, true], selector = [0, 255, true], matching_type = [0, 255, true] }
                  SMIMEA = { usage = [0, 255, true], selector = [0, 255, true], matching_type = [0, 255, true] }
                  SSHFP  = { algorithm = [0, 255, true], type = [0, 255, true] }
                  DS     = { key_tag = [0, 65535, true], algorithm = [0, 255, true], digest_type = [0, 255, true] }
                  DNSKEY = { flags = [0, 65535, true], protocol = [0, 255, true], algorithm = [0, 255, true] }
                  CERT   = { type = [0, 65535, true], key_tag = [0, 65535, true], algorithm = [0, 255, true] }
                  NAPTR  = { order = [0, 65535, true], preference = [0, 65535, true] }
                  LOC = {
                    lat_degrees    = [0, 90, true], lat_minutes = [0, 59, true], lat_seconds = [0, 59.999, false],
                    long_degrees   = [0, 180, true], long_minutes = [0, 59, true], long_seconds = [0, 59.999, false],
                    altitude       = [-100000, 42849672.95, false], size = [0, 90000000, false],
                    precision_horz = [0, 90000000, false], precision_vert = [0, 90000000, false],
                  }
                  }, kind, {}) : [
                  for value in [lookup(coalesce(rec.data, {}), field, null)] : [
                    for n in [try(tonumber(value), null)] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(value)} (${range[2] ? "a whole number" : "a number"} from ${range[0]} to ${range[1]})"
                    if value != null && (n == null ? true : !(n >= range[0] && n <= range[1] && (range[2] ? floor(n) == n : true)))
                  ]
                ]
              ],
              [
                for field, allowed in lookup({ LOC = { lat_direction = ["N", "S", "false"], long_direction = ["E", "W"] } }, kind, {}) : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(lookup(coalesce(rec.data, {}), field, null))} (${join(" or ", [for a in allowed : a if a != "false"])})"
                if lookup(coalesce(rec.data, {}), field, null) != null && !contains(allowed, lookup(coalesce(rec.data, {}), field, ""))
              ],
              [
                for flags in [rec.flags] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.flags: ${flags} (a whole number from 0 to 255)"
                if kind == "CAA" && !(flags == null || (floor(coalesce(flags, 0)) == coalesce(flags, 0) && coalesce(flags, 0) >= 0 && coalesce(flags, 0) <= 255))
              ],
            )
          ]
        ]
      ]
    ]))}"
  }

  # Service parameters of HTTPS and SVCB records as fields of data (RFC 9460), which the
  # module writes into value: alpn and mandatory are comma-separated lists, ipv4hint and
  # ipv6hint comma-separated addresses, ech base64. value holds the same parameters as
  # text, so a record sets one or the other
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : [
              for data in [coalesce(rec.data, {})] : concat(
                lookup(data, "value", null) != null && length(setintersection(keys(data), ["mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"])) > 0 ? ["${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data: value together with ${join(", ", sort(setintersection(keys(data), ["mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"])))} (set the parameters in value or as fields, not both)"] : [],
                [
                  for field, pattern in {
                    alpn      = "^[^,\\s\"\\\\]+(,[^,\\s\"\\\\]+)*$"
                    mandatory = "^(alpn|port|ipv4hint|ech|ipv6hint)(,(alpn|port|ipv4hint|ech|ipv6hint))*$"
                    ech       = "^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"
                  } : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(lookup(data, field, null))}"
                  if lookup(data, field, null) == null ? false : lookup(data, field, null) == "" || !can(regex(pattern, lookup(data, field, null)))
                ],
                [
                  for m in [lookup(data, "mandatory", null)] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.mandatory: ${jsonencode(m)} (each parameter once, and set in data)"
                  if m == null ? false : length(distinct(split(",", m))) != length(split(",", m)) || anytrue([for param in split(",", m) : lookup(data, param, null) == null])
                ],
                [
                  for field in ["ipv4hint", "ipv6hint"] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(lookup(data, field, null))}"
                  if lookup(data, field, null) == null ? false : !alltrue([
                    for address in split(",", lookup(data, field, null)) : field == "ipv4hint" ? can(cidrhost("${address}/32", 0)) && !strcontains(address, ":") : can(cidrhost("${address}/128", 0)) && strcontains(address, ":")
                  ])
                ],
              )
            ]
          ] if contains(["HTTPS", "SVCB"], kind)
        ]
      ]
    ])) == 0
    error_message = "HTTPS and SVCB service parameters must be valid: alpn a comma-separated list of protocol IDs (h2,h3), mandatory a list of other parameters that are set, each once, ipv4hint and ipv6hint comma-separated addresses, ech padded base64, and value only without them:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : [
              for data in [coalesce(rec.data, {})] : concat(
                lookup(data, "value", null) != null && length(setintersection(keys(data), ["mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"])) > 0 ? ["${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data: value together with ${join(", ", sort(setintersection(keys(data), ["mandatory", "alpn", "port", "ipv4hint", "ech", "ipv6hint"])))} (set the parameters in value or as fields, not both)"] : [],
                [
                  for field, pattern in {
                    alpn      = "^[^,\\s\"\\\\]+(,[^,\\s\"\\\\]+)*$"
                    mandatory = "^(alpn|port|ipv4hint|ech|ipv6hint)(,(alpn|port|ipv4hint|ech|ipv6hint))*$"
                    ech       = "^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"
                  } : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(lookup(data, field, null))}"
                  if lookup(data, field, null) == null ? false : lookup(data, field, null) == "" || !can(regex(pattern, lookup(data, field, null)))
                ],
                [
                  for m in [lookup(data, "mandatory", null)] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.mandatory: ${jsonencode(m)} (each parameter once, and set in data)"
                  if m == null ? false : length(distinct(split(",", m))) != length(split(",", m)) || anytrue([for param in split(",", m) : lookup(data, param, null) == null])
                ],
                [
                  for field in ["ipv4hint", "ipv6hint"] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(lookup(data, field, null))}"
                  if lookup(data, field, null) == null ? false : !alltrue([
                    for address in split(",", lookup(data, field, null)) : field == "ipv4hint" ? can(cidrhost("${address}/32", 0)) && !strcontains(address, ":") : can(cidrhost("${address}/128", 0)) && strcontains(address, ":")
                  ])
                ],
              )
            ]
          ] if contains(["HTTPS", "SVCB"], kind)
        ]
      ]
    ]))}"
  }

  # A null MX (RFC 7505) is "." with preference 0
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : (rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]")
            if rec.content == "." && rec.priority != null && rec.priority != 0
          ] if kind == "MX"
        ]
      ]
    ])) == 0
    error_message = "A null MX (content \".\", RFC 7505) must have priority 0:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: priority ${rec.priority}"
            if rec.content == "." && rec.priority != null && rec.priority != 0
          ] if kind == "MX"
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: tag ${jsonencode(rec.tag)}"
            if !contains(["issue", "issuewild", "iodef"], coalesce(rec.tag, "none"))
          ] if kind == "CAA"
        ]
      ]
    ])) == 0
    error_message = "CAA records require a tag: issue, issuewild or iodef:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: tag ${jsonencode(rec.tag)}"
            if !contains(["issue", "issuewild", "iodef"], coalesce(rec.tag, "none"))
          ] if kind == "CAA"
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: key ${jsonencode(rec.key)}"
            if !(rec.key == null || can(regex("^\\S+$", rec.key)))
          ]
        ]
      ]
    ])) == 0
    error_message = "Record key must be a non-empty string without whitespace:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: key ${jsonencode(rec.key)}"
            if !(rec.key == null || can(regex("^\\S+$", rec.key)))
          ]
        ]
      ]
    ]))}"
  }

  validation {
    condition = length(flatten([
      concat(
        [
          for base_name, type_map in var.records : "records[\"${base_name}\"]"
          if !(base_name == "@" || can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$", base_name)))
        ],
        [
          for base_name, type_map in var.records : [
            for raw_key, recs in type_map : "records[\"${base_name}\"][\"${raw_key}\"]: prefix \"${join(".", slice(split(".", raw_key), 0, length(split(".", raw_key)) - 1))}\""
            if length(split(".", raw_key)) > 1 && !can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$", join(".", slice(split(".", raw_key), 0, length(split(".", raw_key)) - 1))))
          ]
        ],
        [
          for base_name, type_map in var.records : [
            for raw_key, recs in type_map : [
              for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
                for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: ${jsonencode(rec.content)}"
                if rec.content != null && !can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$", coalesce(rec.content, "x")))
              ] if kind == "ALIASES"
            ]
          ]
        ],
      )
    ])) == 0
    error_message = "Names, prefixes and ALIASES must be valid DNS names: labels of letters, digits, '_' and '-' (up to 63 characters) separated by dots, optionally starting with '*':\n${join("\n", flatten([
      concat(
        [
          for base_name, type_map in var.records : "records[\"${base_name}\"]"
          if !(base_name == "@" || can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$", base_name)))
        ],
        [
          for base_name, type_map in var.records : [
            for raw_key, recs in type_map : "records[\"${base_name}\"][\"${raw_key}\"]: prefix \"${join(".", slice(split(".", raw_key), 0, length(split(".", raw_key)) - 1))}\""
            if length(split(".", raw_key)) > 1 && !can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$", join(".", slice(split(".", raw_key), 0, length(split(".", raw_key)) - 1))))
          ]
        ],
        [
          for base_name, type_map in var.records : [
            for raw_key, recs in type_map : [
              for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
                for idx, rec in recs : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: ${jsonencode(rec.content)}"
                if rec.content != null && !can(regex("^(\\*|[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*$", coalesce(rec.content, "x")))
              ] if kind == "ALIASES"
            ]
          ]
        ],
      )
    ]))}"
  }

  # DNS names in CNAME, MX, NS and PTR values: labels of letters, digits, '_' and '-' (up to
  # 63 characters) separated by dots, at most 253 characters, an optional trailing dot; not
  # an IP address. "@" is the zone apex, and "." is a null MX (RFC 7505)
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : [
              for value in [coalesce(rec.content, "x")] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: ${kind == "TXT" ? "${length(value)} characters" : jsonencode(rec.content)}"
              if !(
                kind == "A" ? can(cidrhost("${value}/32", 0)) && !strcontains(value, ":") :
                kind == "AAAA" ? can(cidrhost("${value}/128", 0)) && strcontains(value, ":") :
                contains(["CNAME", "MX", "NS", "PTR"], kind) ? (
                  value == "@"
                  || (kind == "MX" && value == ".")
                  || (
                    length(trimsuffix(value, ".")) <= 253
                    && can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", value))
                    && !can(cidrhost("${trimsuffix(value, ".")}/32", 0))
                  )
                ) :
                kind == "TXT" ? length(value) <= 2048 :
                true
              )
            ]
          ]
        ]
      ]
    ])) == 0
    error_message = "A records need an IPv4 address and AAAA records an IPv6 address; CNAME, MX, NS and PTR records need a DNS name (labels of letters, digits, '_' and '-' up to 63 characters, at most 253 in total, not an IP address; \"@\" for the zone apex, \".\" for a null MX); TXT values are limited to 2048 characters:\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : [
              for value in [coalesce(rec.content, "x")] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}: ${kind == "TXT" ? "${length(value)} characters" : jsonencode(rec.content)}"
              if !(
                kind == "A" ? can(cidrhost("${value}/32", 0)) && !strcontains(value, ":") :
                kind == "AAAA" ? can(cidrhost("${value}/128", 0)) && strcontains(value, ":") :
                contains(["CNAME", "MX", "NS", "PTR"], kind) ? (
                  value == "@"
                  || (kind == "MX" && value == ".")
                  || (
                    length(trimsuffix(value, ".")) <= 253
                    && can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", value))
                    && !can(cidrhost("${trimsuffix(value, ".")}/32", 0))
                  )
                ) :
                kind == "TXT" ? length(value) <= 2048 :
                true
              )
            ]
          ]
        ]
      ]
    ]))}"
  }

  # Hostnames in data, with the same rule as CNAME, MX, NS and PTR values. "." is the
  # root: no service for SRV (RFC 2782), the owner name for HTTPS and SVCB (RFC 9460),
  # no replacement for NAPTR (RFC 3403). data is passed to Cloudflare as written, so "@"
  # is not accepted here. A null value becomes "" (invalid): Terraform 1.8 evaluates
  # both sides of ||
  validation {
    condition = length(flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : [
              for field in [kind == "NAPTR" ? "replacement" : "target"] : [
                for raw in [lookup(coalesce(rec.data, {}), field, ".")] : [
                  for value in [raw == null ? "" : raw] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(raw)}"
                  if !(
                    value == "."
                    || (
                      length(trimsuffix(value, ".")) <= 253
                      && can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", value))
                      && !can(cidrhost("${trimsuffix(value, ".")}/32", 0))
                    )
                  )
                ]
              ]
            ]
          ] if contains(["SRV", "HTTPS", "SVCB", "NAPTR"], kind)
        ]
      ]
    ])) == 0
    error_message = "SRV, HTTPS and SVCB targets and NAPTR replacements must be a DNS name (labels of letters, digits, '_' and '-' up to 63 characters, at most 253 in total, not an IP address) or \".\":\n${join("\n", flatten([
      for base_name, type_map in var.records : [
        for raw_key, recs in type_map : [
          for kind in [element(split(".", raw_key), length(split(".", raw_key)) - 1)] : [
            for idx, rec in recs : [
              for field in [kind == "NAPTR" ? "replacement" : "target"] : [
                for raw in [lookup(coalesce(rec.data, {}), field, ".")] : [
                  for value in [raw == null ? "" : raw] : "${rec.source != null ? rec.source : "records[\"${base_name}\"][\"${raw_key}\"][${idx}]"}.data.${field}: ${jsonencode(raw)}"
                  if !(
                    value == "."
                    || (
                      length(trimsuffix(value, ".")) <= 253
                      && can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", value))
                      && !can(cidrhost("${trimsuffix(value, ".")}/32", 0))
                    )
                  )
                ]
              ]
            ]
          ] if contains(["SRV", "HTTPS", "SVCB", "NAPTR"], kind)
        ]
      ]
    ]))}"
  }
}

variable "import_existing" {
  description = "Whether existing_records are matched to the configured records for import. When false, they are only compared to report unmanaged records"
  type        = bool
  default     = true
  nullable    = false
}

variable "existing_records" {
  description = "Records that already exist in the zone, used to find import IDs and unmanaged records. Names are fully qualified, as returned by the Cloudflare API"
  type = list(object({
    id       = string
    name     = string
    type     = string
    content  = optional(string)
    priority = optional(number)
    data     = optional(map(string))
  }))
  default = []
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

variable "unmanaged_ignore" {
  description = "Existing records that are expected in the zone and left out of the report of unmanaged records, e.g. the TXT ownership records of external-dns: a record is left out when it matches all fields of an entry. name_regex is matched (RE2, unanchored: use ^ and $) against the fully qualified name in lower case without a trailing dot, types lists record types"
  type = list(object({
    name_regex = optional(string)
    types      = optional(list(string))
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for i in var.unmanaged_ignore : (i.name_regex != null || i.types != null) && (i.name_regex == null ? true : i.name_regex != "" && can(regexall(i.name_regex, ""))) && length(setsubtract(coalesce(i.types, []), ["A", "AAAA", "CAA", "CERT", "CNAME", "DNSKEY", "DS", "HTTPS", "LOC", "MX", "NAPTR", "NS", "OPENPGPKEY", "PTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "TXT", "URI"])) == 0])
    error_message = "Every unmanaged_ignore entry needs name_regex (a valid, non-empty RE2 expression; an empty one matches every name, leave it out and use types) or types (record types such as TXT), or both."
  }
}
