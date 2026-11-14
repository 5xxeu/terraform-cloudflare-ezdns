output "records" {
  description = "Managed records (sensitive: content of a proxied record is its origin address; pass on record_metadata for the rest)"
  value       = module.dns.records
  sensitive   = true
}
