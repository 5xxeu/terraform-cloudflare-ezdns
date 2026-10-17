# Records with ignore_changes: the attributes listed there come from the record in the
# zone, not from the configuration, so a value changed outside Terraform plans no
# change. Cloudflare does not know the record key, and the configuration cannot read
# the ID in the state, so the record in the zone is found by name and type only. For
# that to stay the same record whatever changes in the configuration or in the zone,
# a record with ignore_changes is the only configured record of its type on its name,
# and the zone has at most one record of that name and type (none: a record not
# created yet, the configured values are used). Matching by value or by priority
# would let the record jump to another one when a neighbour or the priority changes.
locals {
  ignore_change_attributes = ["comment", "content", "proxied", "tags", "ttl"]

  ignored_keys = [for key, rec in local.flat_records : key if length(rec.ignore_changes) > 0]

  live_candidates = {
    for key in local.ignored_keys : key => [
      for e in local.existing : e.id
      if e.type == local.flat_records[key].type && e.name == local.flat_records[key].fqdn
    ]
  }

  existing_by_id = { for r in var.existing_records : r.id => r }
  live_records   = { for key, ids in local.live_candidates : key => length(ids) == 1 ? local.existing_by_id[ids[0]] : null }
  live_ids       = toset([for key, r in local.live_records : r.id if r != null])

  # Configured records per name and type, for the names and types of records with
  # ignore_changes
  configured_per_name = { for key, rec in local.flat_records : "${rec.type} ${rec.fqdn}" => key... }
  ignored_shared = distinct([
    for key in local.ignored_keys : "${local.flat_records[key].type} ${local.flat_records[key].fqdn}: ${length(local.configured_per_name["${local.flat_records[key].type} ${local.flat_records[key].fqdn}"])} configured records"
    if length(local.configured_per_name["${local.flat_records[key].type} ${local.flat_records[key].fqdn}"]) > 1
  ])
  live_ambiguous = [
    for key, ids in local.live_candidates : "${local.flat_records[key].type} ${local.flat_records[key].fqdn}: ${join(", ", ids)}"
    if length(ids) > 1
  ]
  # By the place in the configuration, not the key: a key may contain an origin address
  unknown_ignored = distinct(flatten([
    for r in local.records : [for a in r.ignore_changes : "${r.source}: ${jsonencode(a)}" if !contains(local.ignore_change_attributes, a)]
  ]))
}
