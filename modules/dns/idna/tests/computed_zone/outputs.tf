output "keys" {
  description = "Record keys, known at plan"
  value       = keys(module.dns.records)
}

output "keys_named" {
  description = "Record keys with a zone_name known only after apply, known at plan"
  value       = keys(module.dns_named.records)
}
