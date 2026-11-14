mock_provider "cloudflare" {}

run "duplicates" {
  command = plan

  module {
    source = "../modules/dns/v5"
  }

  variables {
    zone_id   = "z"
    zone_name = "example.com"
    records = { "app" = { TXT = [{ key = "foo", content = "a" }, { key = "foo", content = "b" }] } }
  }
}
