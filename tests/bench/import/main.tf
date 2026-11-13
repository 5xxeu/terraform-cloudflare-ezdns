# Plan time of the import and the report of unmanaged records, with the checks of
# the records (see docs/testing.md):
# `hosts` hosts with an A, a TXT and an MX record each. The zone has the same records,
# half of the A records with another value (an update: their old values are not
# unmanaged), and one stray record per host (unmanaged)

locals {
  records = {
    for i in range(var.hosts) : "h${i}" => {
      A   = [{ key = "a", content = "10.${floor(i / 65536) % 256}.${floor(i / 256) % 256}.${i % 256}" }]
      TXT = [{ content = "v=spf1 -all h${i}" }]
      MX  = [{ content = "mx${i}.example.net", priority = 10 }]
    }
  }
  existing = flatten([
    for i in range(var.hosts) : [
      { id = "a${i}", name = "h${i}.example.com", type = "A", content = i % 2 == 0 ? "10.${floor(i / 65536) % 256}.${floor(i / 256) % 256}.${i % 256}" : "192.0.2.1" },
      { id = "t${i}", name = "h${i}.example.com", type = "TXT", content = "\"v=spf1 -all h${i}\"" },
      { id = "m${i}", name = "h${i}.example.com", type = "MX", content = "mx${i}.example.net", priority = 10 },
      { id = "s${i}", name = "stray${i}.example.com", type = "A", content = "192.0.2.9" },
    ]
  ])
}

module "records" {
  source = "../../../modules/dns/records"

  root_domain      = "example.com"
  records          = local.records
  existing_records = local.existing
  import_existing  = true
}

# The checks over all records, as in the wrappers
module "checks" {
  source = "../../../modules/dns/checks"

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
