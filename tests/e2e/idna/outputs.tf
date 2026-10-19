output "record_names" {
  description = "Names of the managed records, converted to Punycode"
  value       = module.dns.record_names
}
