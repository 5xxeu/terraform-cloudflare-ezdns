# Records with a value known only after apply (a TTL from another resource), for the
# computed_values run of ../groups.tftest.hcl: the keys must stay known at plan, also the
# normalized keys of the records next to them (a content known only after apply is
# planned in scripts/test-plan-checks.py: the check of text values here would wait for
# apply, which terraform test reports as a failure)
resource "terraform_data" "ttl" {
  input = 300
}

module "dns" {
  source    = "../.."
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    "@" = {
      A  = [{ content = "192.0.2.1", ttl = tonumber(terraform_data.ttl.output) }]
      MX = [{ content = "Mail.Example.com.", priority = 10 }]
    }
    "WEB"       = { AAAA = [{ content = "2001:DB8:0::2", ttl = tonumber(terraform_data.ttl.output) }] }
    "_SIP._tcp" = { SRV = [{ data = { priority = "10.0", weight = 5, port = 5060, target = "SIP.example.com." } }] }
  }
  record_groups = {
    web = { records = {
      "www" = { A = [{ content = "192.0.2.2", ttl = tonumber(terraform_data.ttl.output) }] }
      # a name and type that records have too: the lists are joined
      "@" = { A = [{ content = "192.0.2.3", ttl = tonumber(terraform_data.ttl.output) }] }
    } }
  }
}
