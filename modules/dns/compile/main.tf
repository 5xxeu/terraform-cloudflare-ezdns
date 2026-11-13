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
