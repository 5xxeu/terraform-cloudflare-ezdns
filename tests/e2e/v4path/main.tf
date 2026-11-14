# The path of a configuration on provider v4: v2.22.0 on the v4 wrapper, then this
# checkout on the v4 wrapper (moved blocks from state_migration), then this checkout
# on the v5 wrapper (migrate-from-v4.tf). run.sh switches the source and the provider
# version with override files, and applies it all with Terraform 1.9.0. The records
# are written in forms that have another key in 3.0, as in tests/e2e/migrate, so the
# first switch moves records; the CAA record is in the normal form
module "dns" {
  source = "../../../modules/dns/v4"

  zone_id         = var.zone_id
  zone_name       = var.zone_name
  default_ttl     = 300
  default_comment = "ezdns-e2e"
  records = {
    "MIG.${var.prefix}" = {
      A    = [{ content = "192.0.2.20" }]
      AAAA = [{ content = "2001:0DB8:0:0:0:0:0:20" }]
      MX   = [{ content = "mail.${var.zone_name}", priority = 10 }]
      TXT  = [{ content = "ezdns v4 path" }]
      CAA  = [{ content = "letsencrypt.org", tag = "issue" }]
    }
    "_SIP._tcp.mig.${var.prefix}" = {
      SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.${var.zone_name}" } }]
    }
    "WWW.mig.${var.prefix}" = {
      CNAME = [{ content = "alias.mig.${var.prefix}.${var.zone_name}" }]
    }
    "alias.mig.${var.prefix}" = {
      A             = [{ content = "192.0.2.21" }]
      ALIASES       = [{ (var.alias_attribute) = "ALIAS-WWW.mig.${var.prefix}" }]
      "cdn.ALIASES" = [{ (var.alias_attribute) = "cdn-www.mig.${var.prefix}" }]
    }
  }
}
