#!/usr/bin/env sh
# Test of scripts/check-sync.sh: in a copy of the repository, one thing is damaged at a
# time (a block of a wrapper, of the compile or idna submodule or of the root module, a
# missing block, a line past the end of a block that is left out of the comparison, a line
# after braces in a string or a comment), and the script must fail each time. It must
# pass on the untouched copy and on valid changes (braces in strings and comments, the
# alignment of terraform fmt).
#
#   ./scripts/test-check-sync.sh
set -eu

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
failed=0

fresh() {
    rm -rf "$repo"
    mkdir "$repo"
    tar -c --exclude=.git --exclude=.terraform . | tar -x -C "$repo"
}

# edit FILE FROM TO: replaces a line (sed, so no special characters) in the copy
edit() {
    sed "s|$2|$3|" "$repo/$1" >"$repo/$1.new"
    if cmp -s "$repo/$1" "$repo/$1.new"; then
        echo "FAIL $name: the line to change is not in $1" >&2
        failed=1
    fi
    mv "$repo/$1.new" "$repo/$1"
}

# insert FILE HEADER LINE: adds a line after the line that starts with HEADER
insert() {
    awk -v header="$2" -v line="$3" '{ print } index($0, header) == 1 { print line }' "$repo/$1" >"$repo/$1.new"
    mv "$repo/$1.new" "$repo/$1"
}

# before FILE HEADER LINE: adds a line before the line that starts with HEADER
before() {
    awk -v header="$2" -v line="$3" 'index($0, header) == 1 { print line } { print }' "$repo/$1" >"$repo/$1.new"
    mv "$repo/$1.new" "$repo/$1"
}

# drop FILE NAME: removes the block NAME (from its header to the first "}")
drop() {
    sed "/^[a-z]* \"$2\"/,/^}/d" "$repo/$1" >"$repo/$1.new"
    mv "$repo/$1.new" "$repo/$1"
}

# the files that have the variables of the v5 wrapper
variable_files="variables.tf modules/dns/v5/variables.tf modules/dns/v4/variables.tf modules/dns/compile/variables.tf modules/dns/idna/variables.tf"

# verdict WANT: fail or pass of the script on the copy
verdict() {
    if "$repo/scripts/check-sync.sh" >/dev/null 2>&1; then got=pass; else got=fail; fi
    if [ "$got" = "$1" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name: check-sync.sh must $1 on this copy" >&2
        failed=1
    fi
}

# expect_failure NAME FILE FROM TO: one line is changed
expect_failure() {
    name=$1
    fresh
    edit "$2" "$3" "$4"
    verdict fail
}

name="untouched copy"
fresh
verdict pass

expect_failure "prepare call of v4" modules/dns/v4/main.tf '  record_groups = var.record_groups' '  record_groups = {}'
expect_failure "prepare call of compile" modules/dns/compile/main.tf '  record_groups = var.record_groups' '  record_groups = {}'
expect_failure "checks call of v4" modules/dns/v4/main.tf '  not_owned           = module.records.diagnostics.not_owned' '  not_owned           = []'
expect_failure "checks call of compile" modules/dns/compile/main.tf '  not_owned           = module.records.diagnostics.not_owned' '  not_owned           = []'
expect_failure "records call of v4" modules/dns/v4/main.tf '  require_keys            = var.require_keys' '  require_keys            = []'
expect_failure "variables of root" variables.tf 'variable "default_ttl"' 'variable "default_ttl2"'
expect_failure "variables of v4" modules/dns/v4/variables.tf 'variable "default_ttl"' 'variable "default_ttl2"'
expect_failure "variables of compile" modules/dns/compile/variables.tf 'variable "default_ttl"' 'variable "default_ttl2"'
expect_failure "variables of idna" modules/dns/idna/variables.tf 'variable "default_ttl"' 'variable "default_ttl2"'
expect_failure "outputs of root" outputs.tf 'output "record_metadata"' 'output "record_meta"'
expect_failure "outputs of v4" modules/dns/v4/outputs.tf 'output "record_metadata"' 'output "record_meta"'
expect_failure "outputs of idna" modules/dns/idna/outputs.tf 'output "record_names"' 'output "record_names2"'
expect_failure "records of v4 sensitive" modules/dns/v4/outputs.tf '  sensitive = true' '  sensitive = false'
expect_failure "records of compile sensitive" modules/dns/compile/outputs.tf '  sensitive = true' '  sensitive = false'
expect_failure "state_migration of v5 sensitive" modules/dns/v5/outputs.tf '  sensitive   = true$' '  sensitive   = false'
expect_failure "allowed record attributes" modules/dns/records/variables.tf '          priority = optional(number)' '          priority2 = optional(number)'
expect_failure "allowed settings attributes" modules/dns/records/variables.tf '            flatten_cname = optional(bool)' '            flatten_cname2 = optional(bool)'
expect_failure "argument of root" main.tf '  minimum_ttl             = var.minimum_ttl' '  minimum_ttl             = 1'
expect_failure "argument of idna" modules/dns/idna/main.tf '  default_ttl             = var.default_ttl' '  default_tll             = var.default_ttl'
expect_failure "output of root" outputs.tf '  value       = module.v5.records' '  value       = {}'

# a line right past the end of a block that the comparison leaves out of the v4 wrapper
name="line past the end of an excluded block"
fresh
before modules/dns/v4/variables.tf 'variable "default_ttl"' '# stray'
verdict fail
# and of a block that the compile module has in another form (zone_name)
name="line past the end of a block that differs on purpose"
fresh
before modules/dns/compile/variables.tf 'variable "records"' '# stray'
verdict fail

name="a block missing on both sides (checks call)"
fresh
for file in modules/dns/v5/main.tf modules/dns/v4/main.tf modules/dns/compile/main.tf; do drop "$file" checks; done
verdict fail

name="a block missing on both sides (sensitive output)"
fresh
drop modules/dns/compile/outputs.tf records
verdict fail

name="an excluded block that the v5 wrapper no longer has"
fresh
for file in variables.tf modules/dns/v5/variables.tf modules/dns/idna/variables.tf; do drop "$file" unmanaged_policy; done
verdict fail

name="an argument of the root module outside of its call"
fresh
edit main.tf '  minimum_ttl             = var.minimum_ttl' '  minimum_ttl             = 1'
printf 'locals {\n  minimum_ttl = var.minimum_ttl\n}\n' >>"$repo/main.tf"
verdict fail

# braces in a comment and in a string do not end a block: valid, and a line after them
# is still compared
fresh
for file in $variable_files; do
    insert "$file" 'variable "default_ttl"' '  # a } and a { in a comment, "}'
    edit "$file" '  description = "TTL of records that do not set one (1 means automatic)"' '  description = "TTL of records that do not set one } or { (1 means automatic)"'
done
name="braces in a comment and a string"
verdict pass
name="a line after braces in a comment and a string"
edit modules/dns/v4/variables.tf '  default     = 3600' '  default     = 3601'
verdict fail

name="valid formatting after terraform fmt"
fresh
for file in $variable_files; do
    insert "$file" 'variable "default_ttl"' '  sensitive = false'
done
# shellcheck disable=SC2086
(cd "$repo" && terraform fmt $variable_files >/dev/null)
verdict pass

[ "$failed" -eq 0 ] && echo "check-sync.sh catches every damaged block"
exit "$failed"
