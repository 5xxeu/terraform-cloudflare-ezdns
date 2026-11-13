output "count" {
  description = "Records after merging the groups"
  value       = nonsensitive(length(module.compile.records))
}
