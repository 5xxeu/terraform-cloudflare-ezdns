output "record_names" {
  description = "Fully qualified names of all managed records (lower case, from the configuration, so known at plan; one per record)"
  value       = [for key, r in cloudflare_record.record : module.checks.flat_records[key].fqdn if lookup(local.configured_keys, key, false)]
}

output "records" {
  description = "Managed records keyed by their stable identifier: id, zone_id, name (the fully qualified name, lower case, the same as fqdn), fqdn (from the configuration, so known at plan), type, content, ttl, proxied, priority, data (structured records), comment, tags, settings and private_routing (null with provider v4: the attributes are not supported), the last five as configured, e.g. for monitoring or certificates of these names. Sensitive: content and data of a proxied record show its origin address that Cloudflare hides, and a key without an explicit key holds the value; use record_metadata for values that are not secret, or nonsensitive(...) where you accept that"
  value = {
    for key, r in cloudflare_record.record : key => {
      id              = r.id
      zone_id         = r.zone_id
      name            = module.checks.flat_records[key].fqdn
      fqdn            = module.checks.flat_records[key].fqdn
      type            = r.type
      content         = r.content
      ttl             = r.ttl
      proxied         = r.proxied
      priority        = r.priority
      data            = module.checks.flat_records[key].data
      comment         = module.checks.flat_records[key].comment
      tags            = module.checks.flat_records[key].tags
      settings        = null
      private_routing = null
    } if lookup(local.configured_keys, key, false)
  }
  sensitive = true
}

output "record_metadata" {
  description = "Managed records without their values, in the order of their keys: id, zone_id, name (the fully qualified name, the same as fqdn), fqdn, type, ttl, proxied, priority, comment and tags (as in records). Unlike records, it holds no content, data or keys, so it does not show the origin address of a proxied record"
  value = [
    for key, r in cloudflare_record.record : {
      id       = r.id
      zone_id  = r.zone_id
      name     = module.checks.flat_records[key].fqdn
      fqdn     = module.checks.flat_records[key].fqdn
      type     = r.type
      ttl      = r.ttl
      proxied  = r.proxied
      priority = r.priority
      comment  = module.checks.flat_records[key].comment
      tags     = module.checks.flat_records[key].tags
    } if lookup(local.configured_keys, key, false)
  ]
}

output "state_migration" {
  description = "Map of the record keys of module versions 2.x to the current keys, for the records whose key changed in 3.0 (a name or a value written in another form), to generate moved blocks. Sensitive: a key without an explicit key holds the value, such as the origin address of a proxied record; read it with nonsensitive(...) in terraform console (docs/upgrading.md)"
  value       = module.records.state_migration
  sensitive   = true
}
