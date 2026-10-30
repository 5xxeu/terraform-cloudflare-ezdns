output "record_names" {
  description = "Fully qualified names of all managed records (lower case, from the configuration, so known at plan; one per record)"
  value       = module.v5.record_names
}

output "records" {
  description = "Managed records keyed by their stable identifier: id, zone_id, name (as returned by Cloudflare), fqdn (fully qualified, lower case, from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags, settings and private_routing (the last two with provider v5, null with v4), the last five as configured (for a record with ignore_changes, the listed attributes as in the zone), e.g. for monitoring or certificates of these names"
  value       = module.v5.records
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = module.v5.state_migration
}

output "import_ids" {
  description = "Import IDs (<zone_id>/<record_id>) of records that already exist in the zone, keyed by record key. Empty unless import_existing is true; records with no match are left out, and ambiguous matches stop the plan"
  value       = module.v5.import_ids
}

output "import_duplicates" {
  description = "Cloudflare record IDs of existing records that a configured record cannot be matched to unambiguously, keyed by record key. Empty unless import_existing is true; while there are any, the plan stops with this list"
  value       = module.v5.import_duplicates
}

output "presumed_previous_records" {
  description = "Existing records without a match taken as the old values of records that get a new value in this apply (left out of unmanaged_records), with id, name and type. The module cannot see the state, so a record added by hand may be among them. Empty unless report_unmanaged is true"
  value       = module.v5.presumed_previous_records
}

output "matched_records" {
  description = "Existing records that configured records match (by value, or by name and type with ignore_changes), with id, name and type, left out of unmanaged_records. A record of the zone that the state does not hold may be among them, such as a copy of a configured record or one that the plan creates again; tools/plan-guard.py --unmanaged finds those. Empty unless report_unmanaged is true"
  value       = module.v5.matched_records
}

output "unmanaged_records" {
  description = "Records in the zone that the configuration does not describe (id, name, type, content, priority, data). Empty unless report_unmanaged is true. Sensitive: the content of a proxied record is the origin address that Cloudflare hides"
  value       = module.v5.unmanaged_records
  sensitive   = true
}
