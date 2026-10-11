# The records that zone-to-ezdns.py writes from ../fixtures/zone.json, through the module
# (CI writes records.ezdns.yaml first, see the Tools job)
module "dns" {
  source    = "../../.."
  zone_id   = "z"
  zone_name = "example.com"
  records   = yamldecode(file("${path.module}/records.ezdns.yaml")).records
}
