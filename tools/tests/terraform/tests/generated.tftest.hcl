mock_provider "cloudflare" {}

run "generated_records" {
  command = plan

  assert {
    condition     = length(output.keys) == 11
    error_message = "Every record that zone-to-ezdns.py writes from the fixture must be planned"
  }
}
