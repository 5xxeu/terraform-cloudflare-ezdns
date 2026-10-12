output "keys" {
  description = "Record keys, known at plan"
  value       = keys(module.dns.records)
}
