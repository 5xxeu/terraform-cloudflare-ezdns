output "records" {
  description = "The records as the wrappers would create them, keyed by their record key (the key of the Terraform address): name (as sent to Cloudflare), fqdn, type, content, ttl (1 for proxied records), proxied, comment, tags, settings, private_routing, priority and data"
  # Proxied records get TTL 1 (automatic), like in the resources of the wrappers
  value = { for key, r in module.records.flat_records : key => merge(r, { ttl = r.proxied ? 1 : r.ttl }) }
}
