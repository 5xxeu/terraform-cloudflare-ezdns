# Scenario 4: names, prefixes of record types and targets in Unicode through the idna
# submodule. Cloudflare must store the Punycode names the submodule writes, or the
# second plan shows a change

module "dns" {
  source = "../../../modules/dns/idna"

  zone_id         = var.zone_id
  zone_name       = var.zone_name
  default_ttl     = 300
  default_comment = "ezdns-e2e"
  records = {
    "bücher.${var.prefix}" = {
      A            = [{ content = "192.0.2.50" }]
      "straße.TXT" = [{ content = "idna" }]
    }
    "alias-${var.prefix}" = { CNAME = [{ content = "bücher.${var.prefix}.${var.zone_name}" }] }
  }
}
