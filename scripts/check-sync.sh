#!/usr/bin/env sh
# Checks that the copies of the module interface are the same: the root module and the
# idna submodule repeat the variables and outputs of the v5 wrapper, the v4 wrapper and
# the compile module have the variables without the lookup of existing records, and the
# wrappers and the compile module call modules/dns/prepare (merge of record_groups, checks
# of the values), modules/dns/records and modules/dns/checks in the same way.
#
# Supported text (what terraform fmt writes): top-level blocks "module", "variable" and
# "output" with a name in double quotes, the block ends at the first line that starts with
# "}". Braces in strings, comments and nested blocks do not matter, a heredoc with a line
# that starts with "}" would. The files are compared as text, so a block that is missing
# or a file that is empty is an error, also when it is missing on both sides. What still
# depends on the indentation of terraform fmt: the attributes of the call in main.tf
# (two spaces), "sensitive" of an output (two spaces), the optional attributes of the
# records type (10 and 12 spaces) and the lists in the validation of the v5 wrapper.
set -eu

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "$*" >&2
    : >"$tmp/failed"
}

# block FILE NAME: the module, variable or output NAME, from its header to the first "}"
block() {
    awk -v n="$2" '$0 ~ "^(module|variable|output) \"" n "\"" { found = 1 } found { print } found && /^}/ { exit }' "$1"
}

# strip FILE "NAME ..." [headers]: the file without the blocks NAME (and the empty line
# after each), or only the headers of its blocks. A block that is not in the file is
# reported in the text, so it never equals a file that has it, or a missing one
strip() {
    awk -v skip="$2" -v file="$1" -v headers="${3:-}" '
        BEGIN { n = split(skip, list, " "); for (i = 1; i <= n; i++) want[list[i]] = 1 }
        skipping { if (/^}/) { skipping = 0; blank = 1 } next }
        blank && /^$/ { blank = 0; next }
        { blank = 0 }
        /^(module|variable|output) "/ {
            split($0, parts, "\"")
            if (parts[2] in want) { seen[parts[2]] = 1; skipping = 1; next }
        }
        !headers || /^(module|variable|output) "/ { print }
        END { for (name in want) if (!(name in seen)) print "missing block " name " in " file }
    ' "$1"
}

# same LABEL SRC DST: the two texts are the same and not empty
same() {
    printf '%s\n' "$2" >"$tmp/src"
    printf '%s\n' "$3" >"$tmp/dst"
    if [ -z "$2" ]; then
        fail "$1: nothing to compare (the file or the block is missing)"
    elif ! diff -u "$tmp/src" "$tmp/dst"; then
        fail "$1: differs"
    fi
}

# compare SRC DST ABSENT BOTH [headers]: DST is SRC without the blocks ABSENT (DST does not
# have them) and without the blocks BOTH (both have them, in another form)
# shellcheck disable=SC2086
compare() {
    same "$2 and $1 (other than: ${3:-} ${4:-})" "$(strip "$1" "${3:-} ${4:-}" "${5:-}")" "$(strip "$2" "${4:-}" "${5:-}")"
}

lookup="import_existing report_unmanaged unmanaged_ignore unmanaged_policy"
lookup_outputs="import_ids import_duplicates presumed_previous_records matched_records unmanaged_records"
v5=modules/dns/v5

compare $v5/variables.tf variables.tf
compare $v5/outputs.tf outputs.tf "" "" headers
compare $v5/variables.tf modules/dns/v4/variables.tf "$lookup"
compare $v5/outputs.tf modules/dns/v4/outputs.tf "$lookup_outputs" "" headers
compare $v5/variables.tf modules/dns/compile/variables.tf "$lookup zone_id" zone_name
compare $v5/variables.tf modules/dns/idna/variables.tf "" "zone_name owned_names"
compare outputs.tf modules/dns/idna/outputs.tf

# The wrappers pass records and record_groups through the same call of prepare, and the
# records and diagnostics through the same call of checks
for wrapper in modules/dns/compile modules/dns/v4; do
    for call in prepare checks; do
        same "$call call in $wrapper/main.tf" "$(block $v5/main.tf "$call")" "$(block "$wrapper/main.tf" "$call")"
    done
done
# The v4 wrapper calls records like the v5 wrapper, without the arguments of the lookup of
# existing records (provider v4 has none)
core() { block "$1" records | grep -vE '^  (existing_records|import_existing|unmanaged_ignore) ' || true; }
same "records call in modules/dns/v4/main.tf" "$(core $v5/main.tf)" "$(core modules/dns/v4/main.tf)"

# records and state_migration show origin addresses and keys with values: sensitive in
# every module that has them
sensitive() { block "$1" "$2" | awk '/^  sensitive +=/ { print $3; exit }'; }
for file in $v5/outputs.tf modules/dns/v4/outputs.tf outputs.tf modules/dns/idna/outputs.tf; do
    for name in records state_migration; do
        [ "$(sensitive "$file" "$name")" = "true" ] || fail "$file: output $name must be sensitive"
    done
done
[ "$(sensitive modules/dns/compile/outputs.tf records)" = "true" ] || fail "modules/dns/compile/outputs.tf: output records must be sensitive"

# The entry points accept records as any and check attribute names themselves; the
# allowed names must be the attributes of the typed records in the core module (except
# source, which prepare sets for grouped records)
core_attributes() { block modules/dns/records/variables.tf records | sed -nE "s/^ {$1}([a-z0-9_]+) +=.*optional\(.*/\1/p" | grep -vx source | sort; }
allowed() { block $v5/variables.tf records | grep -oE "\\[\"$1\"[^]]*\\]" | head -n 1 | grep -oE '[a-z0-9_]+' | sort; }
same "allowed record attributes in $v5/variables.tf" "$(core_attributes 10)" "$(allowed content)"
same "allowed settings attributes in $v5/variables.tf" "$(core_attributes 12)" "$(allowed flatten_cname)"

# passes FILE MODULE VARIABLES [strict]: the call of MODULE in FILE passes every variable
# of the file VARIABLES (as var.NAME when strict)
passes() {
    grep -oE '^variable "[a-z_]+"' "$3" | cut -d'"' -f2 | while read -r name; do
        value=
        [ "${4:-}" = strict ] && value="var\\.${name}\$"
        block "$1" "$2" | grep -qE "^  ${name} += ${value}" || fail "$1 does not pass ${name} to module.$2"
    done
}
passes main.tf v5 variables.tf strict
passes modules/dns/idna/main.tf v5 modules/dns/idna/variables.tf
# and the root module takes every output from the v5 wrapper
grep -oE '^output "[a-z_]+"' outputs.tf | cut -d'"' -f2 | while read -r name; do
    block outputs.tf "$name" | grep -qE "^  value += module\.v5\.${name}\$" || fail "outputs.tf: output ${name} is not module.v5.${name}"
done

[ ! -e "$tmp/failed" ] || exit 1
echo "Module interfaces are in sync"
