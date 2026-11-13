output "flat_records" {
  description = "Flattened map of records keyed by \"<name> <TYPE> <value>\", ready for for_each. Not checked here: the callers pass it through modules/dns/checks, which fails on the lists of diagnostics"
  value       = local.flat_records
}

output "diagnostics" {
  description = "Invariants over all records, for modules/dns/checks: a list of problems per check (duplicates, same_values, low_ttls, missing_keys, misplaced_wildcards, long_names, self_cnames, not_owned, cname_conflicts), empty when the records pass it, and the context of the messages (owned_include, owned_exclude, minimum_ttl)"
  value = {
    duplicates          = local.duplicates
    same_values         = local.same_values
    low_ttls            = local.low_ttls
    missing_keys        = local.missing_keys
    misplaced_wildcards = local.misplaced_wildcards
    long_names          = local.long_names
    self_cnames         = local.self_cnames
    not_owned           = local.not_owned
    cname_conflicts     = local.cname_conflicts
    owned_include       = local.owned_include
    owned_exclude       = local.owned_exclude
    minimum_ttl         = var.minimum_ttl
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
  description = "Configured records that several existing records match (copies of one record), keyed by record key, with type, name and IDs, also without import_existing; copies that unmanaged_ignore or owned_names leave out of the report are not listed. Sensitive: record keys may contain origin addresses"
  value       = local.report_ambiguous
  sensitive   = true
}

output "presumed_previous_records" {
  description = "Existing records without a match taken as the old values of records that get a new value in this apply (left out of unmanaged_records), with id, name and type. The module cannot see the state, so a record added by hand may be among them"
  value = [
    for r in var.existing_records : { id = r.id, name = r.name, type = r.type }
    if can(local.previous_value_ids[r.id]) && local.reported[r.id]
  ]
}

output "matched_records" {
  description = "Existing records that configured records match (by value, or by name and type with ignore_changes), with id, name and type, left out of unmanaged_records. A match by value also takes another form of the value (TXT with or without quotes, a target in another case), so a record of the zone that the state does not hold may be among them"
  value = [
    for r in var.existing_records : { id = r.id, name = r.name, type = r.type }
    if can(local.matched_ids[r.id]) && local.reported[r.id]
  ]
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
