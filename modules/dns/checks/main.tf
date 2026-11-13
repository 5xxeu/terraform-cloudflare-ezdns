# The checks over all records, with no resources of its own. modules/dns/records builds
# a list of problems per check (output.diagnostics there); each list is an input here
# whose validation fails when it is not empty (variables.tf). A validation can look at its
# own input and at other inputs, but not at locals built from its input (Terraform
# reports a cycle), which is why the lists are built in the records module.
#
# The records reach the resources of the callers through output.flat_records
# (outputs.tf), which waits for every validation: a list known only after apply puts
# its check off until apply, and the records are then not applied before it fails.
