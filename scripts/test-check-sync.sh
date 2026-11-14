#!/usr/bin/env sh
# Negative test of scripts/check-sync.sh: in a copy of the repository, one block of the
# v4 wrapper is damaged at a time, and the script must fail each time (and pass on the
# untouched copy).
#
#   ./scripts/test-check-sync.sh
set -eu

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fresh() {
    rm -rf "$work/repo"
    mkdir "$work/repo"
    tar -c --exclude=.git --exclude=.terraform . | tar -x -C "$work/repo"
}

fresh
if ! "$work/repo/scripts/check-sync.sh" >/dev/null 2>&1; then
    echo "check-sync.sh fails on an untouched copy" >&2
    exit 1
fi

failed=0
# name, file, a line to change, its replacement (sed, so no special characters)
expect_failure() {
    name=$1 file=$2 from=$3 to=$4
    fresh
    sed "s|$from|$to|" "$work/repo/$file" >"$work/repo/$file.new"
    if cmp -s "$work/repo/$file" "$work/repo/$file.new"; then
        echo "FAIL $name: the line to damage is not in $file" >&2
        failed=1
        return
    fi
    mv "$work/repo/$file.new" "$work/repo/$file"
    if "$work/repo/scripts/check-sync.sh" >/dev/null 2>&1; then
        echo "FAIL $name: check-sync.sh passes on a damaged copy" >&2
        failed=1
    else
        echo "ok   $name"
    fi
}

expect_failure "prepare call of v4" modules/dns/v4/main.tf '  record_groups = var.record_groups' '  record_groups = {}'
expect_failure "checks call of v4" modules/dns/v4/main.tf '  not_owned           = module.records.diagnostics.not_owned' '  not_owned           = []'
expect_failure "records call of v4" modules/dns/v4/main.tf '  require_keys            = var.require_keys' '  require_keys            = []'
expect_failure "variables of v4" modules/dns/v4/variables.tf 'variable "default_ttl"' 'variable "default_ttl2"'
expect_failure "outputs of v4" modules/dns/v4/outputs.tf 'output "record_metadata"' 'output "record_meta"'
expect_failure "records of v4 sensitive" modules/dns/v4/outputs.tf '  sensitive = true' '  sensitive = false'
expect_failure "state_migration of v5 sensitive" modules/dns/v5/outputs.tf '  sensitive   = true$' '  sensitive   = false'

[ "$failed" -eq 0 ] && echo "check-sync.sh catches every damaged block"
exit "$failed"
