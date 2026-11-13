# Records with values known only after apply, for the computed_values run of
# ../main.tftest.hcl: a TTL, and a priority on an A record, which does not apply to it
# and fails at apply only (scripts/test-plan-checks.py). Text values known only after
# apply leave the check of numbers in text unknown at plan, a warning that fails a test
# run: scripts/test-plan-checks.py plans them through the compile module
resource "terraform_data" "ttl" {
  input = 300
}

module "prepare" {
  source = "../.."

  records = {
    "@"   = { A = [{ content = "192.0.2.1", ttl = tonumber(terraform_data.ttl.output) }] }
    "app" = { A = [{ content = "192.0.2.2", priority = tonumber(terraform_data.ttl.output) }] }
  }
  record_groups = {
    web = { records = {
      "www" = { A = [{ content = "192.0.2.3", priority = tonumber(terraform_data.ttl.output) }] }
      "@"   = { TXT = [{ content = "text", ttl = tonumber(terraform_data.ttl.output) }] }
    } }
  }
}
