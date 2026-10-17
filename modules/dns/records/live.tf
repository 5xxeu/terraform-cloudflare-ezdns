# Records with ignore_changes: the attributes listed there come from the record in the
# zone, not from the configuration, so a value changed outside Terraform plans no
# change. The record in the zone is found by name and type (Cloudflare does not know
# the key, and the ID in the state cannot be read by the configuration): among the
# existing records of that name and type, the ones that other configured records match
# by value are left out, and exactly one must remain. With none (a record not created
# yet), the configured values are used.
locals {
  ignore_change_attributes = ["comment", "content", "proxied", "tags", "ttl"]

  ignored_keys = [for key, rec in local.flat_records : key if length(rec.ignore_changes) > 0]

  # Existing records that configured records without ignore_changes describe by value
  claimed_by_value = toset(flatten([
    for key, ids in local.report_matches : ids if length(local.flat_records[key].ignore_changes) == 0
  ]))

  live_candidates = {
    for key in local.ignored_keys : key => [
      for e in local.existing : e.id
      if e.type == local.flat_records[key].type && e.name == local.flat_records[key].fqdn && !contains(local.claimed_by_value, e.id)
    ]
  }

  existing_by_id = { for r in var.existing_records : r.id => r }
  live_records   = { for key, ids in local.live_candidates : key => length(ids) == 1 ? local.existing_by_id[ids[0]] : null }

  # Each name and type can have one record with ignore_changes, and it must find at
  # most one record in the zone
  ignored_per_name = { for key in local.ignored_keys : "${local.flat_records[key].type} ${local.flat_records[key].fqdn}" => key... }
  ignored_shared   = [for name, keys in local.ignored_per_name : "${name}: ${length(keys)} records with ignore_changes" if length(keys) > 1]
  live_ambiguous = [
    for key, ids in local.live_candidates : "${local.flat_records[key].type} ${local.flat_records[key].fqdn}: ${join(", ", ids)}"
    if length(ids) > 1
  ]
  unknown_ignored = distinct(flatten([
    for key in local.ignored_keys : [for a in local.flat_records[key].ignore_changes : "${key}: ${a}" if !contains(local.ignore_change_attributes, a)]
  ]))
}
