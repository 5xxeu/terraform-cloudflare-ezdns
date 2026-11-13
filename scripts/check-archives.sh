#!/usr/bin/env sh
# Checks the module archive that release.yml builds before it is published: the files
# a configuration needs are there, tests and CI files are not, and the archive is a
# module that terraform validates.
#
#   ./scripts/check-archives.sh <archive>
set -eu

[ $# -eq 1 ] || { echo "Usage: $0 <archive>" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0

check() {
    name=$1 archive=$2 required=$3 forbidden=$4
    mkdir -p "$work/$name"
    tar -xzf "$archive" -C "$work/$name"
    files=$(cd "$work/$name" && find . -type f | sed 's|^\./||' | sort)
    for file in $required; do
        echo "$files" | grep -qx "$file" || { echo "$name archive: $file is missing" >&2; status=1; }
    done
    unwanted=$(echo "$files" | grep -E "$forbidden" || true)
    [ -z "$unwanted" ] || { echo "$name archive has files that do not belong in it:" >&2; echo "$unwanted" >&2; status=1; }
    if ! (cd "$work/$name" && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color >/dev/null); then
        echo "$name archive: terraform validate failed" >&2
        status=1
    fi
}

common="main.tf variables.tf outputs.tf versions.tf modules/dns/v5/main.tf modules/dns/v5/import.tf modules/dns/records/main.tf schema/records.schema.json README.md CHANGELOG.md LICENSE VERSION"
tests='(^|/)tests/|^\.github/|(^|/)\.terraform|\.tftest\.hcl$'
check full "$1" "$common modules/dns/compile/main.tf modules/dns/idna/main.tf tools/zone-to-ezdns.py tools/plan-guard.py" "$tests"

[ "$status" = 0 ] && echo "Archive is complete"
exit "$status"
