# Records with a value known only after apply (a TTL from another resource) and a list of
# names with such a value (owned_names), for the computed_values run of
# ../main.tftest.hcl: the converted names and the keys must stay known at plan
resource "terraform_data" "ttl" {
  input = 300
}

resource "terraform_data" "name" {
  input = "größe"
}

module "dns" {
  source    = "../.."
  zone_id   = "z"
  zone_name = "münchen.de"
  records = {
    "bücher" = { A = [{ content = "192.0.2.1", ttl = tonumber(terraform_data.ttl.output) }] }
  }
  owned_names = { include = [terraform_data.name.output] }
  record_groups = {
    shop = { records = { "läden" = { A = [{ content = "192.0.2.2", ttl = tonumber(terraform_data.ttl.output) }] } } }
  }
}
