terraform {
  required_version = ">= 1.9.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.41"
    }
  }
}

# Mocked in ../main.tftest.hcl
provider "cloudflare" {}
