output "all_records" {
  description = "records with the records of record_groups merged in, in the form of the records input and with the values as given (not converted to a type): grouped records have the defaults of their group and their source for error messages"
  value       = local.all_records
}
