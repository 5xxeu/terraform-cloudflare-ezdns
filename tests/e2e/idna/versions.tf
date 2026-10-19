terraform {
  required_version = ">= 1.8.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
    # An exact version: the provider runs next to the API token of the test zone, and
    # lock files are not kept. Used by the idna submodule, the pin applies to it
    # tflint-ignore: terraform_unused_required_providers
    idna = {
      source  = "5xxeu/idna"
      version = "= 0.1.0"
    }
  }
}

provider "cloudflare" {}
