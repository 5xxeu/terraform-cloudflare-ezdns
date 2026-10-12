# The records that zone-to-ezdns.py writes from ../fixtures/zone.json, through the module
# (CI writes records.ezdns.yaml first, see the Tools job)
module "dns" {
  source    = "../../.."
  zone_id   = "z"
  zone_name = "example.com"
  # Written by the Tools job of CI; without it (TFLint, a fresh clone) records is empty,
  # and the test fails on the number of records
  records = yamldecode(fileexists("${path.module}/records.ezdns.yaml") ? file("${path.module}/records.ezdns.yaml") : "records: {}").records
}
