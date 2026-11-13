locals {
  root_domain = coalesce(var.zone_name, try(data.cloudflare_zone.this[0].name, null))
  # minimum_ttl = "auto": 30 on Enterprise zones, 60 on the others
  minimum_ttl = var.minimum_ttl != "auto" ? tonumber(var.minimum_ttl) : (
    can(regex("(?i)enterprise", "${coalesce(try(data.cloudflare_zone.this[0].plan.legacy_id, null), "-")} ${coalesce(try(data.cloudflare_zone.this[0].plan.name, null), "-")}")) ? 30 : 60
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
  existing_records        = local.existing_records
  import_existing         = var.import_existing
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = local.minimum_ttl
  owned_names             = var.owned_names
  require_keys            = var.require_keys
  unmanaged_ignore        = var.unmanaged_ignore
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

# Records with ignore_changes get the listed attributes from the record in the zone
locals {
  effective_records = {
    for key, rec in module.checks.flat_records : key => (
      lookup(module.records.live_records, key, null) == null ? rec : merge(rec, {
        # Structured records are sent as data only: the API returns their content too, as
        # text computed from data, and the resource takes one of the two
        content = rec.data != null ? null : contains(rec.ignore_changes, "content") ? module.records.live_records[key].content : rec.content
        data    = contains(rec.ignore_changes, "content") && rec.data != null ? module.records.live_records[key].data : rec.data
        # SRV keeps its priority in data too: the top-level one follows the data in the zone
        priority = contains(rec.ignore_changes, "content") && rec.type == "SRV" ? try(tonumber(module.records.live_records[key].data["priority"]), rec.priority) : rec.priority
        ttl      = contains(rec.ignore_changes, "ttl") ? module.records.live_records[key].ttl : rec.ttl
        proxied  = contains(rec.ignore_changes, "proxied") ? module.records.live_records[key].proxied : rec.proxied
        comment  = contains(rec.ignore_changes, "comment") ? module.records.live_records[key].comment : rec.comment
        tags     = contains(rec.ignore_changes, "tags") ? coalesce(module.records.live_records[key].tags, []) : rec.tags
      })
    )
  }

  # The keys of the configuration, for the outputs over the resources (outputs.tf)
  configured_keys = toset(keys(local.effective_records))
}

resource "cloudflare_dns_record" "record" {
  for_each = local.effective_records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content

  ttl = each.value.proxied ? 1 : each.value.ttl

  # Records with structured data (CAA, SRV, ...) cannot be proxied
  proxied         = each.value.data == null ? each.value.proxied : null
  priority        = each.value.priority
  comment         = each.value.comment
  tags            = length(each.value.tags) > 0 ? each.value.tags : null
  settings        = each.value.settings
  private_routing = each.value.private_routing

  # Numeric flags (CAA, DNSKEY) are sent as numbers, NAPTR flags as a string
  data = each.value.data == null ? null : {
    algorithm      = lookup(each.value.data, "algorithm", null)
    altitude       = lookup(each.value.data, "altitude", null)
    certificate    = lookup(each.value.data, "certificate", null)
    digest         = lookup(each.value.data, "digest", null)
    digest_type    = lookup(each.value.data, "digest_type", null)
    fingerprint    = lookup(each.value.data, "fingerprint", null)
    flags          = try(tonumber(each.value.data["flags"]), lookup(each.value.data, "flags", null))
    key_tag        = lookup(each.value.data, "key_tag", null)
    lat_degrees    = lookup(each.value.data, "lat_degrees", null)
    lat_direction  = lookup(each.value.data, "lat_direction", null)
    lat_minutes    = lookup(each.value.data, "lat_minutes", null)
    lat_seconds    = lookup(each.value.data, "lat_seconds", null)
    long_degrees   = lookup(each.value.data, "long_degrees", null)
    long_direction = lookup(each.value.data, "long_direction", null)
    long_minutes   = lookup(each.value.data, "long_minutes", null)
    long_seconds   = lookup(each.value.data, "long_seconds", null)
    matching_type  = lookup(each.value.data, "matching_type", null)
    order          = lookup(each.value.data, "order", null)
    port           = lookup(each.value.data, "port", null)
    precision_horz = lookup(each.value.data, "precision_horz", null)
    precision_vert = lookup(each.value.data, "precision_vert", null)
    preference     = lookup(each.value.data, "preference", null)
    priority       = lookup(each.value.data, "priority", null)
    protocol       = lookup(each.value.data, "protocol", null)
    public_key     = lookup(each.value.data, "public_key", null)
    regex          = lookup(each.value.data, "regex", null)
    replacement    = lookup(each.value.data, "replacement", null)
    selector       = lookup(each.value.data, "selector", null)
    service        = lookup(each.value.data, "service", null)
    size           = lookup(each.value.data, "size", null)
    tag            = lookup(each.value.data, "tag", null)
    target         = lookup(each.value.data, "target", null)
    type           = lookup(each.value.data, "type", null)
    usage          = lookup(each.value.data, "usage", null)
    value          = lookup(each.value.data, "value", null)
    weight         = lookup(each.value.data, "weight", null)
  }

  lifecycle {
    # Cloudflare routes privately only to the origin of a proxied record and rejects
    # private_routing on the others at apply (error 9232). proxied as it is sent: with
    # ignore_changes = ["proxied"], from the record in the zone
    precondition {
      condition     = each.value.private_routing != true || each.value.proxied == true
      error_message = "${each.value.type} ${each.value.fqdn}: private_routing needs a proxied record (set proxied = true, or remove private_routing)."
    }
  }
}
