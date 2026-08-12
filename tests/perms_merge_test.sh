#!/usr/bin/env bash
# Verifies the permissions.allow merge added to _register_repo_in_org:
#   1) rules land in the org settings.json
#   2) pre-existing allow/deny/ask/env/plugins are preserved
#   3) re-running does not duplicate rules (idempotent)

WORK="${1:?work dir required}"
mkdir -p "$WORK/org/.claude"
cp /home/me/Workspaces/night-district/.claude/settings.json "$WORK/org/.claude/settings.json"

ORG_SETTINGS="$WORK/org/.claude/settings.json"

# Same literal as init.sh line 55
settings_permissions_allow='["Bash(*/.claude/skills/knowledge/load-env.sh)","Bash(*/.claude/skills/knowledge/skills/maintain/maintenance-log.sh)","Bash(*/.claude/skills/knowledge/skills/maintain/audit.sh)","Bash(knowledge *)"]'
org_env=$(jq -n --arg on "night-district" '{ORG_NAME:$on, CLAUDE_SCOPE:"org"}')

# Exact jq from the edited _register_repo_in_org
_merge() {
  jq --argjson env "$org_env" --argjson perms "$settings_permissions_allow" \
    '.env = ((.env // {}) + $env)
     | .permissions.allow = (((.permissions // {}).allow // []) + ($perms - ((.permissions // {}).allow // [])))' \
    "$ORG_SETTINGS"
}

# Hard assertion that a file on disk is well-formed JSON.
# jq empty parses and outputs nothing; nonzero exit means mangled.
_assert_valid_json() {
  local f="$1" label="$2" err
  if ! err=$(jq empty "$f" 2>&1); then
    echo "FAIL: $label produced MANGLED JSON: $err"
    echo "----- raw bytes -----"
    cat "$f"
    exit 1
  fi
  echo "  VALID JSON: $label ($(wc -c < "$f") bytes)"
}

_assert_valid_json "$ORG_SETTINGS" "baseline (untouched copy)"
echo "=== baseline allow count: $(jq '.permissions.allow | length' "$ORG_SETTINGS") ==="

for ((i=1;i<=2;i++)); do
  result=$(_merge) || { echo "FAIL: jq failed on pass $i"; exit 1; }
  printf '%s\n' "$result" > "$ORG_SETTINGS"
  _assert_valid_json "$ORG_SETTINGS" "after pass $i"
  echo "pass $i -> allow count: $(jq '.permissions.allow | length' "$ORG_SETTINGS")"
done

echo
echo "=== allow after two passes ==="
jq -r '.permissions.allow[]' "$ORG_SETTINGS"

echo
echo "=== preserved keys ==="
jq -c '{env, deny:.permissions.deny, ask:.permissions.ask, plugins:.enabledPlugins}' "$ORG_SETTINGS"

echo
echo "=== duplicate check ==="
dupes=$(jq -r '.permissions.allow | group_by(.) | map(select(length>1)) | length' "$ORG_SETTINGS")
echo "duplicate rules: $dupes"

# Empty-file branch: org with no pre-existing settings.json
EMPTY="$WORK/neworg/.claude"
mkdir -p "$EMPTY"
jq -n --argjson env "$org_env" --argjson perms "$settings_permissions_allow" \
  '{env:$env, permissions:{allow:$perms}}' > "$EMPTY/settings.json" \
  || { echo "FAIL: empty-file branch"; exit 1; }
echo
_assert_valid_json "$EMPTY/settings.json" "fresh org settings.json"
echo "=== fresh org settings.json ==="
cat "$EMPTY/settings.json"

# Negative control: prove _assert_valid_json actually catches mangled JSON,
# otherwise a passing suite means nothing.
echo
echo "=== negative control (must be detected) ==="
printf '{"env":{"A":1},"permissions":{"allow":[' > "$WORK/mangled.json"
if jq empty "$WORK/mangled.json" 2>/dev/null; then
  echo "FAIL: truncated JSON was accepted — the validator is useless"
  exit 1
fi
echo "  correctly rejected truncated JSON"
