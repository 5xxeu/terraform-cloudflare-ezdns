# A zone ID known only after apply (a zone created in the same apply) and no zone_name,
# for the computed_zone_id run of ../main.tftest.hcl: the zone is looked up after apply,
# and the plan must not fail on the lookup of the v5 wrapper
resource "terraform_data" "zone" {
  input = "z${timestamp()}"
}

module "dns" {
  source  = "../.."
  zone_id = terraform_data.zone.output
  records = { "bücher" = { A = [{ content = "192.0.2.1" }] } }
}
