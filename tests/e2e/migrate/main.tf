# Records written in forms that 3.0 gives another key (names in upper case, an IPv6
# address not shortened), each a record of its own, so v2.22.0 applies them without
# duplicates. run.sh moves them with the blocks generated from state_migration, as
# docs/upgrading.md describes. Targets stay in lower case: 2.x sends them as written
module "dns" {
  source = "../../.."

  zone_id         = var.zone_id
  zone_name       = var.zone_name
  default_ttl     = 300
  default_comment = "ezdns-e2e"
  records = {
    "MIG.${var.prefix}" = {
      A    = [{ content = "192.0.2.20" }]
      AAAA = [{ content = "2001:0DB8:0:0:0:0:0:20" }]
      MX   = [{ content = "mail.${var.zone_name}", priority = 10 }]
      TXT  = [{ content = "ezdns migrate" }]
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
