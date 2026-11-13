variable "flat_records" {
  description = "output.flat_records of modules/dns/records, passed through by output.flat_records once all checks pass"
  type        = any
  nullable    = false
}

variable "duplicates" {
  description = "Records with the same key, or the same record written in different forms under different keys"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.duplicates) == 0
    error_message = "Duplicate records (remove the duplicates or set a unique key for each of them; MX records that differ only in priority and CAA records that differ only in flags have the same key and need a key too):\n${join("\n", var.duplicates)}"
  }
}

variable "same_values" {
  description = "Records with the same name, type and value under different keys"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.same_values) == 0
    error_message = "Records with the same name, type and value under different keys, which Cloudflare rejects as identical records (remove all but one of them):\n${join("\n", var.same_values)}"
  }
}

variable "low_ttls" {
  description = "TTLs below minimum_ttl, and default_ttl when it is below it"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.low_ttls) == 0
    error_message = "TTLs below ${var.minimum_ttl} seconds are only available on the Cloudflare Enterprise plan. If this zone is on Enterprise, set minimum_ttl = 30 in the module call; otherwise use a TTL of at least 60 seconds, or 1 for automatic:\n${join("\n", var.low_ttls)}"
  }
}

variable "missing_keys" {
  description = "Records of the types in require_keys without a key"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.missing_keys) == 0
    error_message = "require_keys lists the types of these records, so each of them needs a key (e.g. key = \"web\"): with a key, a new value is an update in place, without one the record is deleted and created again:\n${join("\n", var.missing_keys)}"
  }
}

variable "misplaced_wildcards" {
  description = "Names and alias targets with a wildcard other than the whole leftmost label"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.misplaced_wildcards) == 0
    error_message = "A wildcard must be the whole leftmost label of a name (\"*\", \"*.app\"); these names put it elsewhere:\n${join("\n", var.misplaced_wildcards)}"
  }
}

variable "long_names" {
  description = "Fully qualified names and alias targets longer than 253 characters"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.long_names) == 0
    error_message = "A fully qualified name can have at most 253 characters; these names and alias targets (prefix, name and zone together) are longer:\n${join("\n", var.long_names)}"
  }
}

variable "self_cnames" {
  description = "CNAME records (and aliases) that point to their own name"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.self_cnames) == 0
    error_message = "A CNAME (or alias) cannot point to its own name:\n${join("\n", var.self_cnames)}"
  }
}

variable "not_owned" {
  description = "Records outside owned_names"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.not_owned) == 0
    error_message = "These records are outside owned_names (included: ${join(", ", var.owned_include)}; excluded: ${length(var.owned_exclude) == 0 ? "none" : join(", ", var.owned_exclude)}), the part of the zone that this module call manages:\n${join("\n", var.not_owned)}"
  }
}

variable "cname_conflicts" {
  description = "Names where a CNAME shares the name with other records, or with another CNAME"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.cname_conflicts) == 0
    error_message = "A CNAME record cannot share its name with other records (except at the zone apex, where only A and AAAA conflict with it), and a name has at most one CNAME. Names that already have a CNAME next to other records in the zone can be listed in allowed_cname_conflicts:\n${join("\n", var.cname_conflicts)}"
  }
}

# The context of the messages

variable "owned_include" {
  description = "Fully qualified names that owned_names includes (the zone name without owned_names), for the message of not_owned"
  type        = list(string)
  nullable    = false
}

variable "owned_exclude" {
  description = "Fully qualified names that owned_names excludes, for the message of not_owned"
  type        = list(string)
  nullable    = false
}

variable "minimum_ttl" {
  description = "The lowest TTL other than 1 that the records module checked against (60, or 30 on Enterprise zones), for the message of low_ttls"
  type        = number
  nullable    = false
}
