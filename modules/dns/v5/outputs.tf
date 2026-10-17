output "record_names" {
  description = "Fully qualified names of all managed records (lower case, from the configuration, so known at plan; one per record)"
  value       = [for key, r in cloudflare_dns_record.record : module.records.flat_records[key].fqdn]
}

output "records" {
  description = "Managed records keyed by their stable identifier: id, zone_id, name (as returned by Cloudflare), fqdn (fully qualified, lower case, from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags, settings and private_routing (the last two with provider v5, null with v4), the last five as configured (for a record with ignore_changes, the listed attributes as in the zone), e.g. for monitoring or certificates of these names"
  value = {
    for key, r in cloudflare_dns_record.record : key => {
      id              = r.id
      zone_id         = r.zone_id
      name            = r.name
      fqdn            = module.records.flat_records[key].fqdn
      type            = r.type
      content         = r.content
      ttl             = r.ttl
      proxied         = r.proxied
      priority        = r.priority
      data            = local.effective_records[key].data
      comment         = local.effective_records[key].comment
      tags            = local.effective_records[key].tags
      settings        = module.records.flat_records[key].settings
      private_routing = module.records.flat_records[key].private_routing
    }
  }
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = module.records.state_migration
}

output "import_ids" {
  description = "Import IDs (<zone_id>/<record_id>) of records that already exist in the zone, keyed by record key. Empty unless import_existing is true; records with no match are left out, and ambiguous matches stop the plan"
  value       = { for key, id in module.records.import_record_ids : key => "${var.zone_id}/${id}" }
}

output "import_duplicates" {
  description = "Cloudflare record IDs of existing records that a configured record cannot be matched to unambiguously, keyed by record key. Empty unless import_existing is true; while there are any, the plan stops with this list"
  value       = module.records.import_duplicates
}

output "unmanaged_records" {
  description = "Records in the zone that the configuration does not describe (id, name, type, content, priority, data). Empty unless report_unmanaged is true. Sensitive: the content of a proxied record is the origin address that Cloudflare hides"
  value       = [for r in module.records.unmanaged_records : r if var.report_unmanaged]
  sensitive   = true

  # unmanaged_policy = "error": the report stops the plan instead of the warning of
  # check.unmanaged_records (import.tf), with the same list
  precondition {
    condition     = !var.report_unmanaged || var.unmanaged_policy != "error" || length(local.unmanaged_summary) + length(local.ambiguous_summary) == 0
    error_message = join("\n\n", compact([local.unmanaged_message, local.ambiguous_message, "unmanaged_policy is \"error\", so the plan stops."]))
  }
}
