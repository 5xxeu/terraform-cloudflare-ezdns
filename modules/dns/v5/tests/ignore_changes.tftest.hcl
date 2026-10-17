# Records with ignore_changes get the listed attributes from the record in the zone.
# The mocked provider cannot return the nested result list of cloudflare_dns_records,
# so the core is overridden; finding the record in the zone is tested in
# modules/dns/records.

mock_provider "cloudflare" {}

override_module {
  target = module.records
  outputs = {
    flat_records = {
      "_acme-challenge TXT acme" = {
        name           = "_acme-challenge", fqdn = "_acme-challenge.example.com", type = "TXT", content = "init", ttl = 300, proxied = false,
        comment        = "managed", tags = ["team:web"], settings = null, private_routing = null, priority = null, data = null,
        ignore_changes = ["content", "tags"]
      }
      "_sip._tcp SRV sip" = {
        name    = "_sip._tcp", fqdn = "_sip._tcp.example.com", type = "SRV", content = null, ttl = 300, proxied = false,
        comment = null, tags = [], settings = null, private_routing = null, priority = 10,
        data    = { priority = "10", weight = "5", port = "5060", target = "sip.example.com" }, ignore_changes = ["content"]
      }
      "www A 192.0.2.1" = {
        name           = "www", fqdn = "www.example.com", type = "A", content = "192.0.2.1", ttl = 300, proxied = false,
        comment        = null, tags = [], settings = null, private_routing = null, priority = null, data = null,
        ignore_changes = []
      }
    }
    live_records = {
      "_sip._tcp SRV sip" = {
        id   = "id-srv", name = "_sip._tcp.example.com", type = "SRV", content = null, priority = null, ttl = 300, proxied = false, comment = null, tags = null,
        data = { priority = "20", weight = "5", port = "5061", target = "sip2.example.com" }
      }
      "_acme-challenge TXT acme" = {
        id  = "id-acme", name = "_acme-challenge.example.com", type = "TXT", content = "token", priority = null, data = null,
        ttl = 120, proxied = false, comment = "changed in the dashboard", tags = null
      }
    }
    state_migration   = {}
    import_record_ids = {}
    import_duplicates = {}
    ambiguous_matches = {}
    unmanaged_records = []
  }
}

variables {
  zone_id   = "z"
  zone_name = "example.com"
  records   = {}
}

run "listed_attributes_come_from_the_zone" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.record["_acme-challenge TXT acme"].content == "token" && length(local.effective_records["_acme-challenge TXT acme"].tags) == 0
    error_message = "content and tags are taken from the record in the zone"
  }

  assert {
    condition     = cloudflare_dns_record.record["_acme-challenge TXT acme"].ttl == 300 && cloudflare_dns_record.record["_acme-challenge TXT acme"].comment == "managed"
    error_message = "Attributes not listed in ignore_changes stay as configured"
  }

  assert {
    condition     = length(output.records["_acme-challenge TXT acme"].tags) == 0 && output.records["_acme-challenge TXT acme"].comment == "managed"
    error_message = "The records output has the listed attributes as in the zone, the others as configured"
  }

  assert {
    condition     = cloudflare_dns_record.record["_sip._tcp SRV sip"].priority == 20 && cloudflare_dns_record.record["_sip._tcp SRV sip"].data.priority == 20 && cloudflare_dns_record.record["_sip._tcp SRV sip"].data.port == 5061
    error_message = "An SRV record takes data and its priority from the zone together"
  }

  assert {
    condition     = cloudflare_dns_record.record["www A 192.0.2.1"].content == "192.0.2.1"
    error_message = "Records without ignore_changes are as configured"
  }
}
