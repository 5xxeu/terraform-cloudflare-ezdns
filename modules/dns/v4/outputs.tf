output "record_names" {
  description = "Fully qualified names of all managed records (lower case, from the configuration, so known at plan; one per record)"
  value       = [for key, r in cloudflare_record.record : module.records.flat_records[key].fqdn]
}

output "records" {
  description = "Managed records keyed by their stable identifier: id, zone_id, name (as returned by Cloudflare), fqdn (fully qualified, lower case, from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags, settings and private_routing (the last two with provider v5, null with v4), the last five as configured (for a record with ignore_changes, the listed attributes as in the zone), e.g. for monitoring or certificates of these names. Not sensitive: content and data of a proxied record show its origin address that Cloudflare hides, and a key without an explicit key holds the value; pass on record_metadata or sensitive(...) where plans or outputs are logged"
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

output "record_metadata" {
  description = "Managed records without their values, in the order of their keys: id, zone_id, name (as returned by Cloudflare), fqdn, type, ttl, proxied, priority, comment and tags (as in records). Unlike records, it holds no content, data or keys, so it does not show the origin address of a proxied record"
  value = [
    for key, r in cloudflare_record.record : {
      id       = r.id
      zone_id  = r.zone_id
      name     = r.hostname
      fqdn     = module.records.flat_records[key].fqdn
      type     = r.type
      ttl      = r.ttl
      proxied  = r.proxied
      priority = r.priority
      comment  = module.records.flat_records[key].comment
      tags     = module.records.flat_records[key].tags
    }
  ]
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = module.records.state_migration
}
