# Plan time of plain records on the core module (see docs/testing.md):
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
