output "record_names" {
  description = "Fully qualified names of all managed records (lower case, from the configuration, so known at plan; one per record)"
  value       = [for key, r in cloudflare_record.record : module.records.flat_records[key].fqdn]
}

output "records" {
  description = "Managed records keyed by their stable identifier: id, zone_id, name (as returned by Cloudflare), fqdn (fully qualified, lower case, from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags, settings and private_routing (the last two with provider v5, null with v4), the last five as configured (for a record with ignore_changes, the listed attributes as in the zone), e.g. for monitoring or certificates of these names"
  value = {
    for key, r in cloudflare_record.record : key => {
      id              = r.id
      zone_id         = r.zone_id
      name            = r.hostname
      fqdn            = module.records.flat_records[key].fqdn
      type            = r.type
      content         = r.content
      ttl             = r.ttl
      proxied         = r.proxied
      priority        = r.priority
      data            = module.records.flat_records[key].data
      comment         = module.records.flat_records[key].comment
      tags            = module.records.flat_records[key].tags
      settings        = null
      private_routing = null
    }
  }
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = module.records.state_migration
}
