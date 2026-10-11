terraform {
  required_version = ">= 1.8.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
    # Function-only provider (no configuration, no network requests): converts
    # internationalized names to Punycode (UTS #46)
    idna = {
      source  = "5xxeu/idna"
      version = "~> 0.1"
    }
  }
}
