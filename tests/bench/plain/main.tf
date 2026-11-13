# Plan time of plain records on the core module and its checks (see docs/testing.md):
# `hosts` names with an A, an AAAA, a TXT and an MX record each, plus
# `hosts` separate CNAME names, so every type has the same number of records

locals {
  records = merge(
    {
      for i in range(var.hosts) : "h${i}" => {
        A    = [{ content = "10.0.${floor(i / 256) % 256}.${i % 256}" }]
        AAAA = [{ content = "2001:db8::${format("%x", i + 1)}" }]
        TXT  = [{ content = "v=spf1 -all h${i}" }]
        MX   = [{ content = "mx${i}.example.net", priority = 10 }]
      }
    },
    {
      for i in range(var.hosts) : "c${i}" => {
        CNAME = [{ content = "target${i}.example.net" }]
      }
    },
  )
}

module "records" {
  source = "../../../modules/dns/records"

  root_domain = "example.com"
  records     = local.records
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
