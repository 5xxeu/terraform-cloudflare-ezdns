output "keys" {
  description = "Record keys, known at plan"
  value       = nonsensitive(keys(module.dns.records))
}
