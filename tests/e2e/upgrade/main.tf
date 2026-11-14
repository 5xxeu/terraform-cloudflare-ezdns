# Self-contained inputs supported by v2.18.0, independent of the current fixture. The
# ALIASES (inline and with a prefix) keep their keys when the attribute of the name
# changes from content (before 3.0) to name: run.sh sets alias_attribute for the release
module "dns" {
  source = "../../.."

  zone_id         = var.zone_id
  zone_name       = var.zone_name
  default_ttl     = 300
  default_comment = "ezdns-e2e"
  records = {
    "up.${var.prefix}" = {
      A             = [{ content = "192.0.2.10" }, { key = "web", content = "192.0.2.11" }]
      MX            = [{ content = "mail.${var.zone_name}", priority = 10 }]
      TXT           = [{ content = "ezdns upgrade" }]
      ALIASES       = [{ (var.alias_attribute) = "www.up.${var.prefix}" }]
      "cdn.ALIASES" = [{ (var.alias_attribute) = "cdn-www.up.${var.prefix}" }]
    }
    "_sip._tcp.up.${var.prefix}" = {
      SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.${var.zone_name}" } }]
    }
  }
  record_groups = {
    upgrade = {
      records = { "group.up.${var.prefix}" = { A = [{ content = "192.0.2.12" }] } }
    }
  }
}
