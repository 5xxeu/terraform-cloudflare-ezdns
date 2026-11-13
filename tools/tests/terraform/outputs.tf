output "keys" {
  description = "Record keys of the generated records"
  value       = nonsensitive(keys(module.dns.records))
}
