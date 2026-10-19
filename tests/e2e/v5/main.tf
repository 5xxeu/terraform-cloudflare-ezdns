# Scenario 1: all record types through the root module

module "fixture" {
  source = "../fixture"

  prefix    = var.prefix
  zone_name = var.zone_name
  a_value   = var.a_value
  txt_value = var.txt_value
}

module "dns" {
  source = "../../.."

  zone_id          = var.zone_id
  zone_name        = var.zone_name
  default_ttl      = 300
  default_comment  = "ezdns-e2e"
  report_unmanaged = var.report_unmanaged
  unmanaged_policy = var.unmanaged_policy
  # The zone has records of other runs and tools: "error" is checked on this run only
  owned_names = var.unmanaged_policy == "error" ? { include = [var.prefix] } : null
  records     = module.fixture.records
  # A group default wins over default_ttl
  record_groups = { e2e = { records = module.fixture.group_records, defaults = { ttl = 600 } } }
}
