output "unmanaged_records" {
  description = "Records of the zone that the configuration does not describe"
  value       = module.dns.unmanaged_records
  sensitive   = true
}

output "record_names" {
  description = "Names of the managed records, to compare the wrappers"
  value       = module.dns.record_names
}
