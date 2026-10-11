# Records with a value known only after apply (a TTL from another resource), for the
# computed_values run of ../groups.tftest.hcl: the keys must stay known at plan
resource "terraform_data" "ttl" {
  input = 300
}

module "dns" {
  source    = "../.."
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    "@" = { A = [{ content = "192.0.2.1", ttl = tonumber(terraform_data.ttl.output) }] }
  }
  record_groups = {
    web = { records = { "www" = { A = [{ content = "192.0.2.2", ttl = tonumber(terraform_data.ttl.output) }] } } }
  }
}
