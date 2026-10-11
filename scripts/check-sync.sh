#!/usr/bin/env sh
# Checks that the copies of the module interface are the same: the root module
# repeats the variables and outputs of the v5 wrapper, both wrappers and the compile
# module share the records variable, the merge of record_groups and the checks of
# records.
set -eu

cd "$(dirname "$0")/.."
status=0

if ! diff -u modules/dns/v5/variables.tf variables.tf; then
    echo "variables.tf differs from modules/dns/v5/variables.tf" >&2
    status=1
fi

outputs() { grep -E '^output ' "$1"; }
if [ "$(outputs modules/dns/v5/outputs.tf)" != "$(outputs outputs.tf)" ]; then
    echo "outputs.tf does not have the outputs of modules/dns/v5/outputs.tf" >&2
    status=1
fi

records() { awk '/^variable "records"/, /^}/' "$1"; }
# The v4 wrapper has the variables of the v5 wrapper except import_existing,
# report_unmanaged, unmanaged_ignore and unmanaged_policy (provider v4 has no lookup of
# existing records)
without_import() { awk '/^variable "(import_existing|report_unmanaged|unmanaged_ignore|unmanaged_policy)"/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0; getline }' "$1"; }
if ! without_import modules/dns/v5/variables.tf | diff -u - modules/dns/v4/variables.tf; then
    echo "The variables of modules/dns/v4 differ from modules/dns/v5 (other than import_existing, report_unmanaged, unmanaged_ignore and unmanaged_policy)" >&2
    status=1
fi
# Both wrappers merge record_groups and check the text values and unused attributes of
# records the same way: everything from the merge to the end of main.tf, where the
# checks are, is the same
text_checks() { grep -E '^  text_data_fields' "$1"; awk '/^# record_groups merged into records/, /^module "records"/' "$1"; awk '/^# Numbers in text values are written/, 0' "$1"; }
for wrapper in modules/dns/v4 modules/dns/compile; do
    if [ "$(text_checks "$wrapper/main.tf")" != "$(text_checks modules/dns/v5/main.tf)" ]; then
        echo "The merge of record_groups or the checks of records differ between $wrapper/main.tf and modules/dns/v5/main.tf" >&2
        status=1
    fi
done
# The compile module has the variables of the v4 wrapper, with zone_name required and
# without zone_id
without_zone() { awk '/^variable "(zone_id|zone_name)"/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0; getline }' "$1"; }
if [ "$(without_zone modules/dns/v4/variables.tf)" != "$(without_zone modules/dns/compile/variables.tf)" ]; then
    echo "The variables of modules/dns/compile differ from modules/dns/v4 (other than zone_id and zone_name)" >&2
    status=1
fi
# The entry points accept records as any and check attribute names themselves; the
# allowed names must be the attributes of the typed records in the core module (except
# source, which the wrappers set for grouped records)
core_attributes() { records modules/dns/records/variables.tf | sed -nE "s/^ {$1}([a-z0-9_]+) +=.*optional\(.*/\1/p" | grep -vx source | sort; }
allowed() { grep -oE "\\[\"$1\"[^]]*\\]" modules/dns/v5/variables.tf | head -n 1 | grep -oE '[a-z0-9_]+' | sort; }
if [ "$(core_attributes 10)" != "$(allowed content)" ]; then
    echo "The allowed record attributes in modules/dns/v5/variables.tf differ from the records type of modules/dns/records" >&2
    status=1
fi
if [ "$(core_attributes 12)" != "$(allowed flatten_cname)" ]; then
    echo "The allowed settings attributes in modules/dns/v5/variables.tf differ from the records type of modules/dns/records" >&2
    status=1
fi

# The root module passes every input to the v5 wrapper and every output back from it,
# so a missing argument or an output replaced by a constant does not go unnoticed
while read -r name; do
    if ! grep -qE "^  ${name} += var\.${name}\$" main.tf; then
        echo "main.tf does not pass ${name} = var.${name} to module.v5" >&2
        status=1
    fi
done <<EOF
$(grep -oE '^variable "[a-z_]+"' variables.tf | cut -d'"' -f2)
EOF
while read -r name; do
    value=$(awk -v n="$name" '$0 ~ "^output \"" n "\"" { found = 1 } found && /^  value / { print; exit }' outputs.tf)
    if ! printf '%s\n' "$value" | grep -qE "^  value += module\.v5\.${name}\$"; then
        echo "outputs.tf: output ${name} is not module.v5.${name}" >&2
        status=1
    fi
done <<EOF
$(grep -oE '^output "[a-z_]+"' outputs.tf | cut -d'"' -f2)
EOF

# The idna submodule has the interface of the root module: the variables of the v5
# wrapper (zone_name and owned_names without the checks of Punycode names, which the
# v5 wrapper does after the conversion) and the outputs of the root module, and it
# passes every input to its module "v5"
without_names() { awk '/^variable "(zone_name|owned_names)"/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0; getline }' "$1"; }
if [ "$(without_names modules/dns/v5/variables.tf)" != "$(without_names modules/dns/idna/variables.tf)" ]; then
    echo "The variables of modules/dns/idna differ from modules/dns/v5 (other than zone_name and owned_names)" >&2
    status=1
fi
if ! diff -u outputs.tf modules/dns/idna/outputs.tf; then
    echo "modules/dns/idna/outputs.tf differs from outputs.tf" >&2
    status=1
fi
while read -r name; do
    if ! awk '/^module "v5"/, /^}/' modules/dns/idna/main.tf | grep -qE "^  ${name} += "; then
        echo "modules/dns/idna/main.tf does not pass ${name} to module.v5" >&2
        status=1
    fi
done <<EOF
$(grep -oE '^variable "[a-z_]+"' modules/dns/idna/variables.tf | cut -d'"' -f2)
EOF

[ "$status" -eq 0 ] && echo "Module interfaces are in sync"
exit "$status"
