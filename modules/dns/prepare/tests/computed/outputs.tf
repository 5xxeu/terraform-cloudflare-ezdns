output "names" {
  description = "Names and their record types, known at plan"
  value       = { for name, types in module.prepare.all_records : name => join(" ", sort(keys(types))) }
}
