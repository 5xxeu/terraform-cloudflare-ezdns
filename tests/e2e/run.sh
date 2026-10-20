#!/usr/bin/env bash
# End-to-end test against a real Cloudflare zone: creates records of all types
# under a label of this run, checks updates, import, the v4 to v5 migration and
# names in Unicode, an upgrade from the previous release, and deletes everything
# at the end.
#
# Requires CLOUDFLARE_API_TOKEN (DNS Edit on the zone), E2E_ZONE_ID and E2E_ZONE_NAME.
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?}" "${E2E_ZONE_ID:?}" "${E2E_ZONE_NAME:?}"
cd "$(dirname "$0")"
E2E_DIR=$(pwd)
LABEL="${E2E_LABEL:-e2e-$(date +%s)}"
export CLOUDFLARE_API_TOKEN E2E_ZONE_ID
export TF_VAR_zone_id="$E2E_ZONE_ID" TF_VAR_zone_name="$E2E_ZONE_NAME" TF_VAR_prefix="$LABEL"
export TF_IN_AUTOMATION=1 TF_INPUT=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}
pass() { echo "ok - $*"; }
tf() { terraform -chdir="${E2E_DIR}/$1" "${@:2}"; }
# How many of the record_names of a configuration are fully qualified, as "N of M"
# (the names themselves are not printed)
qualified_names() {
    tf "$1" output -json record_names | jq -r --arg zone "${E2E_ZONE_NAME%.}" \
        '"\([.[] | ascii_downcase | rtrimstr(".") | select(. == $zone or endswith("." + $zone))] | length) of \(length)"'
}

# Deletes the records of this run. A failed destroy or sweep fails the run, also when
# all checks passed, and keeps the state files, so the records can still be destroyed
# (otherwise sweep.sh --stale at the start of a later run deletes them)
cleanup() {
    local rc=$? cleaned=1 dir
    set +e
    for dir in upgrade idna v4to5 v4 v5; do
        [ -f "${E2E_DIR}/${dir}/terraform.tfstate" ] || continue
        if ! tf "$dir" destroy -auto-approve -no-color >"${E2E_DIR}/destroy.log" 2>&1; then
            echo "FAIL: destroy of ${dir}: $(tail -20 "${E2E_DIR}/destroy.log")" >&2
            cleaned=0
        fi
    done
    if ! "${E2E_DIR}/sweep.sh" "$LABEL"; then
        echo "FAIL: sweep of the records of ${LABEL}" >&2
        cleaned=0
    fi
    if [ "$cleaned" = 1 ]; then
        rm -rf "${E2E_DIR}/.upgrade-from" "${E2E_DIR}/upgrade/source_override.tf"
        rm -rf "${E2E_DIR}"/*/terraform.tfstate* "${E2E_DIR}"/*/tfplan "${E2E_DIR}"/ids*
    else
        echo "Records of ${LABEL} may be left in the zone, the state files are kept" >&2
        [ "$rc" != 0 ] || rc=1
    fi
    exit "$rc"
}
# A tag on HEAD is this release, so compare with the release before it.
upgrade_from=${E2E_UPGRADE_FROM:-}
if [ -n "$upgrade_from" ]; then
    git show-ref --verify --quiet "refs/tags/${upgrade_from}" || fail "E2E_UPGRADE_FROM must name an available tag"
else
    head_commit=$(git rev-parse HEAD)
    while read -r tag; do
        [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        tag_commit=$(git rev-parse "refs/tags/${tag}^{commit}")
        [ "$tag_commit" != "$head_commit" ] || continue
        if git merge-base --is-ancestor "$tag_commit" HEAD; then
            upgrade_from=$tag
            break
        fi
    done < <(git tag --merged HEAD --sort=-version:refname)
    [ -n "$upgrade_from" ] || fail "no previous vX.Y.Z ancestor tag available, fetch full history and tags or set E2E_UPGRADE_FROM"
fi
trap cleanup EXIT

# Prints how many resources a saved plan creates, deletes, updates, imports and moves
plan_summary() {
    # A failed plan must not summarize a stale tfplan.
    local rc=0
    tf "$1" plan -no-color -out=tfplan "${@:2}" >"${E2E_DIR}/plan.log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        tail -40 "${E2E_DIR}/plan.log" >&2
        return "$rc"
    fi
    tf "$1" show -json tfplan | jq -r '
        [.resource_changes[]? | select(.mode == "managed")] as $rc |
        "create=\([$rc[] | select(.change.actions | index("create"))] | length) " +
        "delete=\([$rc[] | select(.change.actions | index("delete"))] | length) " +
        "update=\([$rc[] | select(.change.actions == ["update"])] | length) " +
        "import=\([$rc[] | select(.change.importing)] | length) " +
        "move=\([$rc[] | select(.previous_address and .previous_address != .address)] | length)"'
}

# Prints "<record key> <Cloudflare record ID>" for the records in the state, sorted by key.
# Only the resources under .values: the checks of a resource with a precondition list
# its address too, without an index or values
record_ids() {
    tf "$1" show -json | jq -r '
        [.values | .. | objects | select(.mode? == "managed" and (.type? == "cloudflare_dns_record" or .type? == "cloudflare_record"))]
        | map("\(.index) \(.values.id)") | sort[]'
}

# Fails unless two lists of record IDs are the same: no record was recreated
assert_same_ids() {
    [ -s "$2" ] || fail "$1: no records in the state"
    diff -u "$2" "$3" >"${E2E_DIR}/ids.diff" || fail "$1: record IDs differ: $(head -40 "${E2E_DIR}/ids.diff")"
}

# Fails when the plan has any change: the provider would show a perpetual diff
assert_no_changes() {
    local rc=0
    tf "$1" plan -no-color -detailed-exitcode "${@:2}" >"${E2E_DIR}/plan.log" || rc=$?
    [ "$rc" -eq 0 ] || fail "$1: expected no changes, plan exit code $rc: $(grep -E '^  #|~ |\+ |- ' "${E2E_DIR}/plan.log" | head -40)"
}

# The names of the zone and the records are public, so they are not printed
echo "Label: ${LABEL}"
"${E2E_DIR}/sweep.sh" --stale

for dir in v5 import v4 v4to5 idna; do tf "$dir" init -no-color >/dev/null; done

# Scenario 1: create all record types, then check there is no drift
tf v5 apply -auto-approve -no-color >"${E2E_DIR}/apply.log" || fail "apply: $(tail -40 "${E2E_DIR}/apply.log")"
count=$(tf v5 state list | grep -c 'cloudflare_dns_record.record\[')
pass "created ${count} records of all types"
assert_no_changes v5
pass "no drift after apply"
names=$(qualified_names v5)
[ "${names% of *}" = "${names#* of }" ] || fail "v5: record_names are not all fully qualified (${names})"
pass "v5: record_names fully qualified (${names})"
# The TTL default of the group wins over default_ttl (300)
ttls=$(tf v5 show -json | jq -r '[.values | .. | objects | select(.mode? == "managed" and .type? == "cloudflare_dns_record") | .values | select(.name | startswith("grp.")) | .ttl] | "\(length) \(unique | join(","))"')
[ "$ttls" = "2 600" ] || fail "record_groups: expected 2 records with the group TTL 600, got ${ttls}"
pass "record_groups: records of a group created with the TTL default of the group"

# While values change, the records with the old values are in the state, not
# unmanaged: the report lets the update through, also with unmanaged_policy = "error"
# (limited to the label of this run with owned_names, since the zone has records of
# other runs and tools)
tf v5 plan -no-color -out=tfplan -var a_value=192.0.2.20 -var txt_value=rotation=2 -var report_unmanaged=true -var unmanaged_policy=error >"${E2E_DIR}/plan.log" 2>&1 ||
    fail "plan of new values with unmanaged_policy = error: $(grep -E 'Error' "${E2E_DIR}/plan.log" | head -20)"
reported=$(tf v5 show -json tfplan | jq -r '.planned_values.outputs.unmanaged_records.value | length')
[ "$reported" = 0 ] || fail "report_unmanaged lists ${reported} records of the module while their values change"
pass "unmanaged_policy = error: no record of the module reported while values change"

# Changing a value without a key replaces the record, with a key updates it in place
summary=$(plan_summary v5 -var a_value=192.0.2.20 -var txt_value=rotation=2)
[ "$summary" = "create=1 delete=1 update=1 import=0 move=0" ] || fail "value changes: ${summary}"
tf v5 apply -auto-approve -no-color tfplan >/dev/null
assert_no_changes v5 -var a_value=192.0.2.20 -var txt_value=rotation=2
pass "value change: record without key replaced, record with key updated in place"
record_ids v5 >"${E2E_DIR}/ids-v5.txt"

# The report of unmanaged records lists a record created outside the module, and none
# of the records of the module. Only records of this run are compared, since the zone
# has records of other tools. The stray record is deleted by sweep.sh (same comment
# and label)
api="https://api.cloudflare.com/client/v4/zones/${E2E_ZONE_ID}/dns_records"
stray_id=$(curl -fsS -X POST -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "$api" \
    -d "$(jq -n --arg name "stray.${LABEL}.${E2E_ZONE_NAME}" '{type: "TXT", name: $name, content: "\"ezdns stray\"", ttl: 300, comment: "ezdns-e2e"}')" | jq -r .result.id)
if [ -z "$stray_id" ] || [ "$stray_id" = null ]; then fail "could not create the stray record"; fi
tf v5 plan -no-color -out=tfplan -var a_value=192.0.2.20 -var txt_value=rotation=2 -var report_unmanaged=true >"${E2E_DIR}/plan.log" 2>&1 ||
    fail "plan with report_unmanaged: $(grep -E 'Error' "${E2E_DIR}/plan.log" | head -20)"
reported=$(tf v5 show -json tfplan | jq -r --arg label "$LABEL" '[.planned_values.outputs.unmanaged_records.value[] | select(.name | contains($label)) | .id] | sort | join(" ")')
[ "$reported" = "$stray_id" ] || fail "report_unmanaged: expected only ${stray_id} of this run, got '${reported}'"
grep -q "records that the configuration does not describe" "${E2E_DIR}/plan.log" || fail "report_unmanaged: no plan warning"
pass "report_unmanaged lists the stray record and none of the module"
rc=0
tf v5 plan -no-color -var a_value=192.0.2.20 -var txt_value=rotation=2 -var report_unmanaged=true -var unmanaged_policy=error >"${E2E_DIR}/plan.log" 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "unmanaged_policy = error: the plan passes with a stray record under the label"
grep -q 'unmanaged_policy is "error"' "${E2E_DIR}/plan.log" || fail "unmanaged_policy = error: the plan fails for another reason: $(grep -E 'Error' "${E2E_DIR}/plan.log" | head -5)"
pass "unmanaged_policy = error stops the plan for the stray record"

# A record with ignore_changes = ["content"] keeps a value changed outside Terraform
acme_id=$(record_ids v5 | grep ' TXT acme ' | awk '{print $NF}')
[ -n "$acme_id" ] || fail "ignore_changes: the record is not in the state"
curl -fsS -X PATCH -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${api}/${acme_id}" \
    -d '{"content": "\"changed outside\""}' >/dev/null || fail "ignore_changes: could not change the record"
srv_id=$(record_ids v5 | grep ' SRV xmpp ' | awk '{print $NF}')
[ -n "$srv_id" ] || fail "ignore_changes: the SRV record is not in the state"
curl -fsS -X PATCH -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" "${api}/${srv_id}" \
    -d "$(jq -n --arg target "xmpp2.${E2E_ZONE_NAME}" '{data: {priority: 20, weight: 5, port: 5270, target: $target}}')" >/dev/null ||
    fail "ignore_changes: could not change the SRV record"
assert_no_changes v5 -var a_value=192.0.2.20 -var txt_value=rotation=2
pass "ignore_changes: a TXT content and SRV data changed outside Terraform plan no change"

# Scenario 2: the same records are adopted into an empty state. Provider v5 plans a
# one-time update without visible changes for imported structured records (SRV, ...)
summary=$(plan_summary import -var a_value=192.0.2.20 -var txt_value=rotation=2)
case "$summary" in
    "create=0 delete=0 update="*" import=${count} move=0") ;;
    *) fail "import: ${summary}, expected import=${count} and nothing created or deleted" ;;
esac
tf import apply -auto-approve -no-color tfplan >/dev/null
assert_no_changes import -var a_value=192.0.2.20 -var txt_value=rotation=2
# Every record was adopted with the ID of the record created in scenario 1
record_ids import >"${E2E_DIR}/ids-import.txt"
assert_same_ids "import" "${E2E_DIR}/ids-v5.txt" "${E2E_DIR}/ids-import.txt"
# The records stay managed by the state of scenario 1, which deletes them
rm -f "${E2E_DIR}/import/terraform.tfstate"*
pass "all ${count} records imported, no drift afterwards (${summary})"

# Scenario 3: records created with provider v4 are moved to v5 without recreation
tf v4 apply -auto-approve -no-color >"${E2E_DIR}/apply.log" || fail "v4 apply: $(tail -40 "${E2E_DIR}/apply.log")"
assert_no_changes v4
pass "provider v4: created records without drift"
names=$(qualified_names v4)
[ "${names% of *}" = "${names#* of }" ] || fail "v4: record_names are not all fully qualified (${names})"
pass "v4: record_names fully qualified (${names})"
record_ids v4 >"${E2E_DIR}/ids-v4.txt"
cp "${E2E_DIR}/v4/terraform.tfstate" "${E2E_DIR}/v4to5/terraform.tfstate"
rm -f "${E2E_DIR}/v4/terraform.tfstate"
summary=$(plan_summary v4to5)
case "$summary" in
    "create=0 delete=0 "*) ;;
    *) fail "v4 to v5 migration: ${summary}" ;;
esac
# Provider v5 may report an inconsistent modified_on (different precision than in the
# migrated state) for some records on this first apply; the records are updated and
# the next plan is empty, so only this error is tolerated until
# https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387 is fixed
only_modified_on_inconsistency() {
    local attributes
    grep -q "Provider produced inconsistent result after apply" "$1" || return 1
    attributes=$(grep -oE "unexpected new value: \.[a-z_]+" "$1" | sed 's/.*\.//' | sort -u)
    [ "$attributes" = "modified_on" ]
}
if ! tf v4to5 apply -auto-approve -no-color tfplan >"${E2E_DIR}/apply.log" 2>&1; then
    only_modified_on_inconsistency "${E2E_DIR}/apply.log" || fail "v4 to v5 apply: $(tail -40 "${E2E_DIR}/apply.log")"
    echo "note: provider reported the known modified_on inconsistency after the migration"
fi
assert_no_changes v4to5
# The same records under the same keys: moved, not recreated
record_ids v4to5 >"${E2E_DIR}/ids-v4to5.txt"
assert_same_ids "v4 to v5 migration" "${E2E_DIR}/ids-v4.txt" "${E2E_DIR}/ids-v4to5.txt"
pass "v4 to v5 migration without recreating records, same IDs (${summary})"

# Scenario 4: names, a prefix of a record type and a CNAME target in Unicode through
# the idna submodule, stored in Punycode without drift
tf idna apply -auto-approve -no-color >"${E2E_DIR}/apply.log" || fail "idna apply: $(tail -40 "${E2E_DIR}/apply.log")"
assert_no_changes idna
names=$(qualified_names idna)
[ "${names% of *}" = "${names#* of }" ] || fail "idna: record_names are not all fully qualified (${names})"
punycode=$(tf idna output -json record_names | jq '[.[] | select(startswith("xn--"))] | length')
[ "$punycode" = 2 ] || fail "idna: expected 2 names in Punycode, got ${punycode}"
pass "idna: records with names in Unicode created in Punycode without drift (${names})"

# Scenario 5: upgrade the previous release to this checkout without losing records.
# The override changes only the source, removing it restores ../../.. in main.tf.
mkdir -p "${E2E_DIR}/.upgrade-from"
# Archive from the repository root, git archive otherwise uses the current subdirectory.
git -C "$(git rev-parse --show-toplevel)" archive "refs/tags/${upgrade_from}" | tar -x -C "${E2E_DIR}/.upgrade-from"
if ! grep -q '^module "v5" {' "${E2E_DIR}/.upgrade-from/main.tf" ||
    [ ! -f "${E2E_DIR}/.upgrade-from/modules/dns/v5/main.tf" ]; then
    fail "upgrade: archive of ${upgrade_from} does not contain the root module and v5 wrapper"
fi
cat >"${E2E_DIR}/upgrade/source_override.tf" <<'EOF'
module "dns" {
  source = "../.upgrade-from"
}
EOF
tf upgrade init -no-color >"${E2E_DIR}/upgrade.log" 2>&1 || fail "upgrade: init of ${upgrade_from}: $(tail -40 "${E2E_DIR}/upgrade.log")"
tf upgrade apply -auto-approve -no-color >"${E2E_DIR}/upgrade.log" 2>&1 || fail "upgrade: apply of ${upgrade_from}: $(tail -40 "${E2E_DIR}/upgrade.log")"
record_ids upgrade >"${E2E_DIR}/ids-upgrade-before.txt"
# Capture addresses before moved blocks in the new source can rewrite the prior state.
tf upgrade show -json | jq '
    [.values | .. | objects |
        select(.mode? == "managed" and .type? == "cloudflare_dns_record") | .address] | sort
' >"${E2E_DIR}/ids-upgrade-addresses.json"
rm "${E2E_DIR}/upgrade/source_override.tf"
tf upgrade init -no-color >"${E2E_DIR}/upgrade.log" 2>&1 || fail "upgrade: init of current checkout: $(tail -40 "${E2E_DIR}/upgrade.log")"
summary=$(plan_summary upgrade) || fail "upgrade: plan failed"
# Check the saved plan's actions, including both orders of a replacement.
tf upgrade show -json tfplan | jq -e --slurpfile before "${E2E_DIR}/ids-upgrade-addresses.json" '
    [.resource_changes[]? | select(.mode == "managed" and .type == "cloudflare_dns_record")] as $rc |
    ($rc | length) > 0 and
    all($rc[]; .change.actions == ["no-op"] or .change.actions == ["update"]) and
    $before[0] == ([$rc[] | .previous_address // .address] | sort)
' >/dev/null || fail "upgrade: expected only no-op, in-place updates or explicit moves (${summary})"
tf upgrade apply -auto-approve -no-color tfplan >"${E2E_DIR}/upgrade.log" 2>&1 || fail "upgrade: apply of saved plan: $(tail -40 "${E2E_DIR}/upgrade.log")"
record_ids upgrade >"${E2E_DIR}/ids-upgrade-after.txt"
assert_same_ids "upgrade" "${E2E_DIR}/ids-upgrade-before.txt" "${E2E_DIR}/ids-upgrade-after.txt"
assert_no_changes upgrade
pass "upgrade from ${upgrade_from}: same record IDs, no drift (${summary})"

echo "All end-to-end checks passed"
