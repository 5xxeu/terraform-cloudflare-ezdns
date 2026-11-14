locals {
  root_domain = coalesce(var.zone_name, try(data.cloudflare_zone.this[0].name, null))
  # minimum_ttl = "auto": 30 on Enterprise zones, 60 on the others
  minimum_ttl = var.minimum_ttl != "auto" ? tonumber(var.minimum_ttl) : (
    can(regex("(?i)enterprise", coalesce(try(data.cloudflare_zone.this[0].plan, null), "-"))) ? 30 : 60
  )
}

# record_groups merged into records, and the checks that need the values as given
module "prepare" {
  source = "../prepare"

  records       = var.records
  record_groups = var.record_groups
}

module "records" {
  source = "../records"

  root_domain             = local.root_domain
  records                 = module.prepare.all_records
  import_existing         = false
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = local.minimum_ttl
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

data "cloudflare_zone" "this" {
  count   = var.zone_name == null || var.minimum_ttl == "auto" ? 1 : 0
  zone_id = var.zone_id

  lifecycle {
    # Cloudflare returns the name of an internationalized zone in Unicode, while
    # record names come back in Punycode (only the name of the lookup is used: with
    # zone_name set, the zone is read for its plan with minimum_ttl = "auto")
    postcondition {
      condition     = var.zone_name != null || !can(regex("[^[:ascii:]]", self.name))
      error_message = "The zone ${jsonencode(self.name)} has an internationalized name, which Cloudflare returns in Unicode: set zone_name in Punycode (xn--mnchen-3ya.de for münchen.de; provider::idna::to_ascii of the 5xxeu/idna provider converts it)."
    }
  }
}

# The keys of the configuration, for the outputs over the resources (outputs.tf): a
# map, so a lookup does not go through all keys, and its values stay known
locals {
  configured_keys = { for key in keys(module.checks.flat_records) : key => true }
}

resource "cloudflare_record" "record" {
  for_each = module.checks.flat_records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content

  ttl = each.value.proxied ? 1 : each.value.ttl

  # Records with structured data (CAA, SRV, ...) cannot be proxied
  proxied  = each.value.data == null ? each.value.proxied : null
  priority = each.value.priority
  comment  = each.value.comment
  tags     = length(each.value.tags) > 0 ? each.value.tags : null

  dynamic "data" {
    for_each = each.value.data == null ? [] : [each.value.data]
    content {
      algorithm      = lookup(data.value, "algorithm", null)
      altitude       = lookup(data.value, "altitude", null)
      certificate    = lookup(data.value, "certificate", null)
      digest         = lookup(data.value, "digest", null)
      digest_type    = lookup(data.value, "digest_type", null)
      fingerprint    = lookup(data.value, "fingerprint", null)
      flags          = lookup(data.value, "flags", null)
      key_tag        = lookup(data.value, "key_tag", null)
      lat_degrees    = lookup(data.value, "lat_degrees", null)
      lat_direction  = lookup(data.value, "lat_direction", null)
      lat_minutes    = lookup(data.value, "lat_minutes", null)
      lat_seconds    = lookup(data.value, "lat_seconds", null)
      long_degrees   = lookup(data.value, "long_degrees", null)
      long_direction = lookup(data.value, "long_direction", null)
      long_minutes   = lookup(data.value, "long_minutes", null)
      long_seconds   = lookup(data.value, "long_seconds", null)
      matching_type  = lookup(data.value, "matching_type", null)
      order          = lookup(data.value, "order", null)
      port           = lookup(data.value, "port", null)
      precision_horz = lookup(data.value, "precision_horz", null)
      precision_vert = lookup(data.value, "precision_vert", null)
      preference     = lookup(data.value, "preference", null)
      priority       = lookup(data.value, "priority", null)
      protocol       = lookup(data.value, "protocol", null)
      public_key     = lookup(data.value, "public_key", null)
      regex          = lookup(data.value, "regex", null)
      replacement    = lookup(data.value, "replacement", null)
      selector       = lookup(data.value, "selector", null)
      service        = lookup(data.value, "service", null)
      size           = lookup(data.value, "size", null)
      tag            = lookup(data.value, "tag", null)
      target         = lookup(data.value, "target", null)
      type           = lookup(data.value, "type", null)
      usage          = lookup(data.value, "usage", null)
      value          = lookup(data.value, "value", null)
      weight         = lookup(data.value, "weight", null)
    }
  }

  lifecycle {
    # Provider v4 has no lookup of the records of a zone, which ignore_changes reads
    # the values from: rather than sending the configured values (and undoing a change
    # made outside Terraform), the plan stops
    precondition {
      condition     = length(each.value.ignore_changes) == 0
      error_message = "${each.value.type} ${each.value.fqdn}: ignore_changes needs provider v5 (the root module); the v4 wrapper does not support it."
    }
  }
}


# Provider v4 has no settings and private_routing: the attributes are accepted (the
# configuration stays the same for both providers) and ignored, which a warning makes
# visible. Only the values that ask for something are listed; false is the default.
# Records are of type any here, so "true" (a string in YAML or JSON) counts too
locals {
  v5_only_attributes = flatten([
    for name, types in module.prepare.all_records : [
      for type, list in types : [
        for index, record in list : concat(
          [
            for setting in ["flatten_cname", "ipv4_only", "ipv6_only"] : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.settings.${setting}"
            if try(tobool(record.settings[setting]), null) == true
          ],
          [for attribute in ["private_routing"] : "${try(record.source, "records[\"${name}\"][\"${type}\"][${index}]")}.${attribute}" if try(tobool(record[attribute]), null) == true],
        )
      ]
    ]
  ])
}

check "records_v5_only_attributes" {
  assert {
    condition     = length(local.v5_only_attributes) == 0
    error_message = "These attributes need provider v5 (the root module) and are ignored by the v4 wrapper:\n${join("\n", local.v5_only_attributes)}"
  }
}
