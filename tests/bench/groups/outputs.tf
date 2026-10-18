output "count" {
  description = "Records after merging the groups"
  value       = length(module.compile.records)
}
