output "counts" {
  description = "Imported records (all but the A records with another value) and unmanaged records (one stray per host)"
  value = {
    imported  = nonsensitive(length(module.records.import_record_ids))
    unmanaged = nonsensitive(length(module.records.unmanaged_records))
  }
}
