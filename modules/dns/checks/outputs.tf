output "flat_records" {
  description = "flat_records as given, once every check has passed: the resources of the callers take their records from here, so a check put off until apply (a list known only after apply) fails before any record is created or changed"
  value       = var.flat_records

  # Without depends_on the output would not wait for the validations of the other
  # inputs, and the records would be applied before a check that waits for apply fails.
  # The lists are not part of the value: an unknown list would make the keys of the
  # records unknown at plan
  depends_on = [
    var.duplicates,
    var.same_values,
    var.low_ttls,
    var.missing_keys,
    var.misplaced_wildcards,
    var.long_names,
    var.self_cnames,
    var.not_owned,
    var.cname_conflicts,
  ]
}
