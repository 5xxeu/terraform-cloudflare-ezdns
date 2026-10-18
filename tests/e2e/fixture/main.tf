# Records used by the end-to-end scenarios. All names are the label of the run or
# below it, so runs do not collide, the cleanup finds them, and owned_names = [label]
# limits the report of unmanaged records to this run.

locals {
  p = var.prefix
  z = var.zone_name
}
