output "keys" {
  description = "Record keys of the generated records"
  value       = keys(module.dns.records)
}
