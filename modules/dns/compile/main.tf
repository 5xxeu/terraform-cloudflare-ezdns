# record_groups merged into records, and the checks that need the values as given
module "prepare" {
  source = "../prepare"

  records       = var.records
  record_groups = var.record_groups
}

module "records" {
  source = "../records"

  root_domain             = var.zone_name
  records                 = module.prepare.all_records
  import_existing         = false
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = var.minimum_ttl == "auto" ? 30 : tonumber(var.minimum_ttl)
  owned_names             = var.owned_names
  require_keys            = var.require_keys
}

# The checks over all records: the records reach the resources through this module, so
# a check put off until apply fails before any record is created or changed
module "checks" {
  source = "../checks"

  flat_records        = module.records.flat_records
  duplicates          = module.records.diagnostics.duplicates
  same_values         = module.records.diagnostics.same_values
  low_ttls            = module.records.diagnostics.low_ttls
  missing_keys        = module.records.diagnostics.missing_keys
  misplaced_wildcards = module.records.diagnostics.misplaced_wildcards
  long_names          = module.records.diagnostics.long_names
  self_cnames         = module.records.diagnostics.self_cnames
  not_owned           = module.records.diagnostics.not_owned
  cname_conflicts     = module.records.diagnostics.cname_conflicts
  owned_include       = module.records.diagnostics.owned_include
  owned_exclude       = module.records.diagnostics.owned_exclude
  minimum_ttl         = module.records.diagnostics.minimum_ttl
}
