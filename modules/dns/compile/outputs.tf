output "records" {
  description = "The records as the wrappers would create them, keyed by their record key (the key of the Terraform address): name (as sent to Cloudflare), fqdn, type, content, ttl, proxied, comment, tags, settings, priority and data"
  value       = module.records.flat_records
}
