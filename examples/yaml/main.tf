# Records kept in a YAML file. Files named *.ezdns.yaml can be mapped to the JSON
# Schema of the module in editors, for completion and validation (see the README).
module "dns" {
  # Outside of this repository, from the Terraform Registry (see the README for a local copy or Git):
  #   source  = "5xxeu/ezdns/cloudflare"
  #   version = "2.21.0"
  source = "../.."

  zone_id         = var.zone_id
  zone_name       = var.zone_name
  default_comment = "Managed by Terraform"

  records = yamldecode(file("${path.module}/records.ezdns.yaml")).records
}
