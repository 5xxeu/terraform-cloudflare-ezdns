output "unmanaged_records" {
  description = "Records of the zone that the configuration does not describe"
  value       = module.dns.unmanaged_records
  sensitive   = true
}

output "record_names" {
  description = "Names of the managed records, to compare the wrappers"
  value       = module.dns.record_names
}

output "presumed_previous_records" {
  description = "Records taken as the old values of changed records, for plan-guard --unmanaged"
  value       = module.dns.presumed_previous_records
}

output "matched_records" {
  description = "Records of the zone that configured records match, for plan-guard --unmanaged"
  value       = module.dns.matched_records
}
