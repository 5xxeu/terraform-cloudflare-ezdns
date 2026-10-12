# A zone ID known only after apply (a zone created in the same apply) and no zone_name,
# and a zone_name known only after apply, for the computed_zone runs of
# ../main.tftest.hcl: the plan must not fail on the zone lookup of the v5 wrapper, and the
# keys of the records must stay known
resource "terraform_data" "zone" {
  input = "z${timestamp()}"
}

module "dns" {
  source  = "../.."
  zone_id = terraform_data.zone.output
  records = { "bücher" = { A = [{ content = "192.0.2.1" }] } }
}

module "dns_named" {
  source    = "../.."
  zone_id   = "z"
  zone_name = "münchen.de${substr(timestamp(), 0, 0)}"
  records   = { "bücher" = { A = [{ content = "192.0.2.1" }] } }
}
