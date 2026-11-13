output "count" {
  description = "Flattened records"
  value       = length(module.checks.flat_records)
}
