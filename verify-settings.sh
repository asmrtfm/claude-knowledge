#!/usr/bin/env bash
# Verify that settings files match the expected state after init.
# Can be sourced from init.sh (all vars already set) or run standalone.
#
# Standalone usage: ./verify-settings.sh [target_dir]
#   Reads .envrc from target_dir (default: pwd) to populate env vars,
#   then derives MODE and SETTINGS from what's on disk.

# ── Bootstrap when run standalone ──
if [[ -z "$TARGET" ]]; then
  TARGET="$(realpath "${1:-.}")"
  ENVRC="$TARGET/.envrc"
  [[ -f "$ENVRC" ]] || { echo "[ERROR] No .envrc found in $TARGET" >&2; exit 1; }
  source "$ENVRC"

  # Derive MODE from CLAUDE_SCOPE (set by .envrc)
  case "${CLAUDE_SCOPE:-}" in
    org)     MODE="org" ;;
    project) MODE="project" ;;
    *)       MODE="repo" ;;
  esac

  # Detect which settings file has the knowledge hooks
  for _candidate in "$TARGET/.claude/settings.json" "$TARGET/.claude/settings.local.json"; do
    if jq -e '.hooks.PreToolUse' "$_candidate" >/dev/null 2>&1; then
      SETTINGS="$_candidate"
      break
    fi
  done
  [[ -n "$SETTINGS" ]] || { echo "[ERROR] No hooks found in either settings file" >&2; exit 1; }
fi


# ─────────────────────────────────────────────────────────────────────────────────
_vfail=0

# Assert jq query == expected
_chk() {
  local label="$1" expected="$2" file="$3" query="$4"
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null)
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label (expected: $expected, got: $actual)"
    ((_vfail++)) || true
  fi
}

# Assert jq array contains value
_chk_contains() {
  local label="$1" needle="$2" file="$3" query="$4"
  if jq -e "$query" "$file" 2>/dev/null | grep -qF "$needle"; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label (expected to contain: $needle)"
    ((_vfail++)) || true
  fi
}

echo ""
echo "── verifying settings ──"

_sj="$TARGET/.claude/settings.json"
_sl="$TARGET/.claude/settings.local.json"

# settings.json: portable vars (CLAUDE_SCOPE + names)
case "$MODE" in
  org)
    _chk "settings.json: ORG_NAME" "$ORG_NAME" "$_sj" '.env.ORG_NAME'
    _chk "settings.json: CLAUDE_SCOPE" "org" "$_sj" '.env.CLAUDE_SCOPE'
    ;;
  project)
    _chk "settings.json: PROJECT_NAME" "$PROJECT_NAME" "$_sj" '.env.PROJECT_NAME'
    _chk "settings.json: CLAUDE_SCOPE" "project" "$_sj" '.env.CLAUDE_SCOPE'
    ;;
  *)
    _chk "settings.json: REPO_NAME" "$REPO_NAME" "$_sj" '.env.REPO_NAME'
    _chk "settings.json: CLAUDE_SCOPE" "repo" "$_sj" '.env.CLAUDE_SCOPE'
    ;;
esac

# settings.local.json: absolute paths
case "$MODE" in
  org)     _chk "settings.local.json: ORG_DIR" "$ORG_DIR" "$_sl" '.env.ORG_DIR' ;;
  project) _chk "settings.local.json: PROJECT_ROOT" "$PROJECT_ROOT" "$_sl" '.env.PROJECT_ROOT' ;;
  *)       _chk "settings.local.json: REPO_ROOT" "$REPO_ROOT" "$_sl" '.env.REPO_ROOT' ;;
esac

# Knowledge hook commands present in the chosen settings file
_hook_cmds=$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command, .hooks.PostToolUse[]?.hooks[]?.command] | .[]' "$SETTINGS" 2>/dev/null)
for _script in pre-search.sh pre-edit.sh maintenance-queue.sh; do
  if echo "$_hook_cmds" | grep -qF "knowledge/$_script"; then
    echo "  ✓ ${SETTINGS##*/}: $_script hook"
  else
    echo "  ✗ ${SETTINGS##*/}: $_script hook missing"
    ((_vfail++)) || true
  fi
done

# Org settings (repo mode with org)
if [[ "$MODE" == "repo" && -n "$ORG_DIR" ]]; then
  _oj="$ORG_DIR/.claude/settings.json"
  _ol="$ORG_DIR/.claude/settings.local.json"

  _chk "org settings.json: ORG_NAME" "$ORG_NAME" "$_oj" '.env.ORG_NAME'
  _chk "org settings.json: CLAUDE_SCOPE" "org" "$_oj" '.env.CLAUDE_SCOPE'
  _chk "org settings.local.json: ORG_DIR" "$ORG_DIR" "$_ol" '.env.ORG_DIR'
  _chk_contains "org settings.local.json: additionalDirectories has repo" \
    "$REPO_ROOT" "$_ol" '.permissions.additionalDirectories[]'

  # Repo also gets org vars
  _chk "repo settings.json: ORG_NAME" "$ORG_NAME" "$_sj" '.env.ORG_NAME'
  _chk "repo settings.local.json: ORG_DIR" "$ORG_DIR" "$_sl" '.env.ORG_DIR'
fi

if ((_vfail > 0)); then
  echo ""
  echo "  ⚠ $_vfail verification(s) failed — review settings files"
else
  echo ""
  echo "  all checks passed"
fi
