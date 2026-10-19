terraform {
  required_version = ">= 1.8.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
    idna = {
      source  = "5xxeu/idna"
      version = "~> 0.1"
    }
  }
}

provider "cloudflare" {}
