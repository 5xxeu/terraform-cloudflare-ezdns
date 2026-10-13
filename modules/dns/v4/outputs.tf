output "record_names" {
  description = "Hostnames of all managed records"
  value       = [for r in cloudflare_record.record : r.hostname]
}

output "records" {
  description = "Managed records keyed by their stable identifier: id, zone_id, name (as returned by Cloudflare), fqdn (fully qualified, lower case, from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags and settings (provider v5; null with v4), the last four as configured, e.g. for monitoring or certificates of these names"
  value = {
    for key, r in cloudflare_record.record : key => {
      id       = r.id
      zone_id  = r.zone_id
      name     = r.hostname
      fqdn     = module.records.flat_records[key].fqdn
      type     = r.type
      content  = r.content
      ttl      = r.ttl
      proxied  = r.proxied
      priority = r.priority
      data     = module.records.flat_records[key].data
      comment  = module.records.flat_records[key].comment
      tags     = module.records.flat_records[key].tags
      settings = null
    }
  }
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = module.records.state_migration
}
