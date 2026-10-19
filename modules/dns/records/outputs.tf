output "flat_records" {
  description = "Flattened map of records keyed by \"<name> <TYPE> <value>\", ready for for_each"
  value       = local.flat_records

  precondition {
    condition     = length(local.duplicates) == 0
    error_message = "Duplicate records (remove the duplicates or set a unique key for each of them; MX records that differ only in priority and CAA records that differ only in flags have the same key and need a key too):\n${join("\n", local.duplicates)}"
  }

  precondition {
    condition     = length(local.same_values) == 0
    error_message = "Records with the same name, type and value under different keys, which Cloudflare rejects as identical records (remove all but one of them):\n${join("\n", local.same_values)}"
  }

  precondition {
    condition     = length(local.low_ttls) == 0
    error_message = "TTLs below ${var.minimum_ttl} seconds are only available on the Cloudflare Enterprise plan. If this zone is on Enterprise, set minimum_ttl = 30 in the module call; otherwise use a TTL of at least 60 seconds, or 1 for automatic:\n${join("\n", local.low_ttls)}"
  }

  precondition {
    condition     = length(local.misplaced_wildcards) == 0
    error_message = "A wildcard must be the whole leftmost label of a name (\"*\", \"*.app\"); these names put it elsewhere:\n${join("\n", local.misplaced_wildcards)}"
  }

  precondition {
    condition     = length(local.long_names) == 0
    error_message = "A fully qualified name can have at most 253 characters; these names and alias targets (prefix, name and zone together) are longer:\n${join("\n", local.long_names)}"
  }

  precondition {
    condition     = length(local.self_cnames) == 0
    error_message = "A CNAME (or alias) cannot point to its own name:\n${join("\n", local.self_cnames)}"
  }

  precondition {
    condition     = length(local.not_owned) == 0
    error_message = "These records are outside owned_names (included: ${join(", ", local.owned_include)}; excluded: ${length(local.owned_exclude) == 0 ? "none" : join(", ", local.owned_exclude)}), the part of the zone that this module call manages:\n${join("\n", local.not_owned)}"
  }

  precondition {
    condition     = length(local.cname_conflicts) == 0
    error_message = "A CNAME record cannot share its name with other records (except at the zone apex, where only A and AAAA conflict with it), and a name has at most one CNAME. Names that already have a CNAME next to other records in the zone can be listed in allowed_cname_conflicts:\n${join("\n", local.cname_conflicts)}"
  }
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = local.state_migration
}

output "import_record_ids" {
  description = "Cloudflare record IDs of existing_records matching the configured records, keyed by record key. Records with no match are left out; ambiguous matches stop the plan (see import_duplicates)"
  value       = local.import_record_ids

  # An ambiguous import would plan the record as new, and the API rejects it at
  # apply (or keeps two copies of it), so the plan stops here instead
  precondition {
    condition     = length(local.import_duplicates) == 0
    error_message = "These records cannot be imported unambiguously: each matches several existing records, or the same existing record as other configured records. Remove the duplicates from the zone or give the records distinct values or priorities; to import such a record anyway, set import_existing = false and write an import block for it:\n${join("\n", [for key, ids in local.import_duplicates : "\"${key}\": ${join(", ", ids)}"])}"
  }
}

output "import_duplicates" {
  description = "Cloudflare record IDs of existing_records that a configured record cannot be matched to unambiguously, keyed by record key. While there are any, import_record_ids fails and the plan stops"
  value       = local.import_duplicates
}

output "ambiguous_matches" {
  description = "Configured records that several existing records match (copies of one record), keyed by record key, with type, name and IDs, also without import_existing. Sensitive: record keys may contain origin addresses"
  value       = local.report_ambiguous
  sensitive   = true
}

output "unmanaged_records" {
  description = "existing_records that no configured record matches: records in the zone that the configuration does not describe. Sensitive: the content of a proxied record is the origin address that Cloudflare hides"
  value       = local.unmanaged_records
  sensitive   = true
}


output "live_records" {
  description = "Records with ignore_changes, keyed like flat_records: the record of the same name and type in the zone (id, content, data, ttl, proxied, comment, tags), or null when the zone has none yet"
  value       = local.live_records

  precondition {
    condition     = length(local.unknown_ignored) == 0
    error_message = "ignore_changes can list content (with data), ttl, proxied, comment and tags:\n${join("\n", local.unknown_ignored)}"
  }

  precondition {
    condition     = length(local.ignored_shared) == 0
    error_message = "A record with ignore_changes is found in the zone by its name and type, so it must be the only configured record of its type on its name (other records of the type can go on another name, or without ignore_changes):\n${join("\n", local.ignored_shared)}"
  }

  precondition {
    condition     = length(local.live_ambiguous) == 0
    error_message = "A record with ignore_changes is found in the zone by its name and type, and the zone has several records of that name and type (delete the extra records in the zone):\n${join("\n", local.live_ambiguous)}"
  }
}
