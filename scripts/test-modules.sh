#!/usr/bin/env sh
# Runs init, validate and test in every directory of the test job of CI
# (.github/workflows/ci.yml), with the given Terraform binary (default: terraform):
#
#   ./scripts/test-modules.sh
#   ./scripts/test-modules.sh ~/bin/terraform-1.8.0
set -eu

cd "$(dirname "$0")/.."
terraform=${1:-terraform}
case "$terraform" in
    */*) terraform=$(cd "$(dirname "$terraform")" && pwd)/$(basename "$terraform") ;;
esac
"$terraform" version | head -n 1

dirs=$(awk '/^        dir:/ { list = 1; next } list && /^          - / { print $2; next } list { exit }' .github/workflows/ci.yml)
[ -n "$dirs" ] || { echo "No test directories found in .github/workflows/ci.yml" >&2; exit 1; }

failed=""
for dir in $dirs; do
    echo "== $dir"
    if ! (cd "$dir" && "$terraform" init -backend=false -input=false >/dev/null && "$terraform" validate -no-color >/dev/null && "$terraform" test -no-color >test.log 2>&1); then
        tail -n 40 "$dir/test.log" 2>/dev/null || true
        failed="$failed $dir"
    fi
    tail -n 1 "$dir/test.log" 2>/dev/null || true
    rm -f "$dir/test.log"
done

if [ -n "$failed" ]; then
    echo "Failed:$failed" >&2
    exit 1
fi
