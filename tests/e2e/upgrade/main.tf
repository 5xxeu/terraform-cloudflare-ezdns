# Self-contained inputs supported by v2.18.0, independent of the current fixture.
module "dns" {
  source = "../../.."

  zone_id         = var.zone_id
  zone_name       = var.zone_name
  default_ttl     = 300
  default_comment = "ezdns-e2e"
  records = {
    "up.${var.prefix}" = {
      A   = [{ content = "192.0.2.10" }, { key = "web", content = "192.0.2.11" }]
      MX  = [{ content = "mail.${var.zone_name}", priority = 10 }]
      TXT = [{ content = "ezdns upgrade" }]
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
