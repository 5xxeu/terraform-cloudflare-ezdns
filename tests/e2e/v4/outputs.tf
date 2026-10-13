
output "record_names" {
  description = "Names of the managed records, to compare the wrappers"
  value       = module.dns.record_names
}
