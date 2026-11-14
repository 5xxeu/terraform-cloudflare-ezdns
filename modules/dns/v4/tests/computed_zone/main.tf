# A zone ID known only after apply (a zone created in the same apply) and no zone_name,
# and a zone_name known only after apply, for the computed_zone run of ../main.tftest.hcl:
# the plan must not fail on the zone lookup of the wrapper, and the keys of the records
# must stay known (a content known only after apply is planned in
# scripts/test-plan-checks.py: the check of text values would wait for apply, which
# terraform test reports as a failure)
resource "terraform_data" "zone" {
  input = "z${timestamp()}"
}

module "dns" {
  source  = "../.."
  zone_id = terraform_data.zone.output
  records = { "app" = { A = [{ key = "a", content = "192.0.2.1" }] } }
}

module "dns_named" {
  source    = "../.."
  zone_id   = "z"
  zone_name = "example.com${substr(timestamp(), 0, 0)}"
  records = {
    "app" = { A = [{ key = "a", content = "192.0.2.1" }] }
    # Normalized keys need no zone name
    "Shop" = { AAAA = [{ content = "2001:DB8::1" }] }
  }
}
