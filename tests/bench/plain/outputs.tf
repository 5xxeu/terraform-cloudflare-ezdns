output "count" {
  description = "Flattened records"
  value       = length(module.records.flat_records)
}
