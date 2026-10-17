# Plan time of the import and the report of unmanaged records (see docs/testing.md):
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
