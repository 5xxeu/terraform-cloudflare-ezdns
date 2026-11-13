output "records" {
  description = "Sensitive (content and data of a proxied record are its origin address). The records as the wrappers would create them, keyed by their record key (the key of the Terraform address): name (as sent to Cloudflare), fqdn, type, content, ttl (1 for proxied records), proxied, comment, tags, settings, private_routing, priority and data"
  # Proxied records get TTL 1 (automatic), like in the resources of the wrappers
  value     = { for key, r in module.checks.flat_records : key => merge(r, { ttl = r.proxied ? 1 : r.ttl }) }
  sensitive = true
}
