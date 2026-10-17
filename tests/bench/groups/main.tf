# Plan time of merging record_groups and of the CNAME checks (see docs/testing.md):
# `hosts` names in records with an A record each, and `groups` groups with `hosts` names
# each: half of the names of a group are also in records, half are new. Every tenth
# name in records also has a CNAME and is listed in allowed_cname_conflicts

locals {
  records = {
    for i in range(var.hosts) : "h${i}" => merge(
      { A = [{ content = "10.0.${floor(i / 256) % 256}.${i % 256}" }] },
      i % 10 == 0 ? { CNAME = [{ content = "target.example.net" }] } : {},
    )
  }
  record_groups = {
    for g in range(var.groups) : "g${g}" => {
      defaults = { ttl = 300 }
      records = {
        for i in range(var.hosts) : i % 2 == 0 ? "h${i}" : "g${g}h${i}" => {
          TXT = [{ content = "group ${g} host ${i}" }]
        }
      }
    }
  }
}

module "compile" {
  source = "../../../modules/dns/compile"

  zone_name               = "example.com"
  records                 = local.records
  record_groups           = local.record_groups
  allowed_cname_conflicts = [for i in range(var.hosts) : "h${i}" if i % 10 == 0]
}
