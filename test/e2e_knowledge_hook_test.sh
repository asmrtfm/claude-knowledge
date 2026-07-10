#!/usr/bin/env bash
# End-to-end tests for the knowledge hook pipeline:
#   knowledge.sh -> resolve-env.sh -> query-knowledge.sh
#
# Exercises all modes: search types (grep/rg/find), non-search passthrough,
# match vs no-match, layered lookup (org+project), skip modes (ast-grep,
# non-recursive grep), and the disable mechanism.

set -uo pipefail
shopt -s extglob

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "$SCRIPT_DIR/helpers/assert.sh"
HOOK="$SCRIPT_DIR/../.claude/hooks/knowledge/knowledge.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

export REPO_ROOT="$FIXTURES/project"
export ORG_DIR="$FIXTURES/org"
unset PROJECT_ROOT 2>/dev/null || true

echo "── e2e: knowledge hook pipeline ──"

# Feed a command through the hook, return raw JSON output
run_hook() {
  local json
  json=$(jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}')
  printf '%s' "$json" | bash "$HOOK" 2>/dev/null
}

# Extract the updatedInput.command from hook output
get_updated_cmd() {
  local out
  out=$(run_hook "$1") || true
  [[ -n "$out" ]] || return 0
  printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty'
}

# Check if the hook allowed without modifying the command
is_passthrough() {
  local out
  out=$(run_hook "$1") || true
  [[ -z "$out" ]] && return 0
  local has_updated
  has_updated=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput // empty')
  [[ -z "$has_updated" ]]
}

# ── Non-search commands: silent passthrough ──

result=$(run_hook 'ls -la')
assert_empty "ls passes through silently" "$result"

result=$(run_hook 'cat README.md')
assert_empty "cat passes through silently" "$result"

result=$(run_hook 'git status')
assert_empty "git status passes through silently" "$result"

result=$(run_hook 'npm install')
assert_empty "npm install passes through silently" "$result"

# ── Skip modes ──

result=$(run_hook 'ast-grep -p "console.log($$$)" src/')
assert_empty "ast-grep is not intercepted" "$result"

result=$(run_hook 'grep -n "pattern" file.txt')
assert_empty "non-recursive grep is not intercepted" "$result"

result=$(run_hook 'grep "pattern" file.txt')
assert_empty "grep without flags is not intercepted" "$result"

# ── INDEX-based lookup (primary path) ──

# "order" appears on the left side of INDEX.md (file paths)
updated=$(get_updated_cmd 'grep -rn "order" app/')
assert_contains "INDEX hit: prepends knowledge header" "=== KNOWLEDGE ENTRIES ===" "$updated"
assert_contains "INDEX hit: surfaces index lines" "order" "$updated"
assert_contains "INDEX hit: original command preserved" 'grep -rn "order" app/' "$updated"

# "actioncable" appears on the right side of INDEX.md (entry paths)
updated=$(get_updated_cmd 'grep -rn "actioncable" app/')
assert_contains "INDEX right-side: matches entry path" "actioncable" "$updated"

# "checkout" appears on the right side via entry path (order-lifecycle -> checkout_service)
updated=$(get_updated_cmd 'grep -rn "checkout" app/')
assert_contains "INDEX right-side: checkout matches" "checkout" "$updated"

# ── Recursive grep with stacked flags ──

updated=$(get_updated_cmd 'grep -rni --color=never "order" app/')
assert_contains "grep -rni stacked: has knowledge output" "KNOWLEDGE ENTRIES" "$updated"

# ── rg with matches ──

updated=$(get_updated_cmd 'rg "order" app/')
assert_contains "rg: prepends knowledge header" "=== KNOWLEDGE ENTRIES ===" "$updated"
assert_contains "rg: includes scored results" "order" "$updated"
assert_contains "rg: original command preserved" 'rg "order" app/' "$updated"

# ── rg with flags ──

updated=$(get_updated_cmd 'rg -i --hidden "cache" app/')
assert_contains "rg with flags: has knowledge output" "KNOWLEDGE ENTRIES" "$updated"
assert_contains "rg with flags: matches cache entry" "cache" "$updated"

# ── find with matches ──

updated=$(get_updated_cmd 'find . -name "order*.rb"')
assert_contains "find -name: prepends knowledge header" "=== KNOWLEDGE ENTRIES ===" "$updated"
assert_contains "find -name: includes scored results" "order" "$updated"
assert_contains "find -name: original command preserved" 'find . -name "order*.rb"' "$updated"

# ── find -iname ──

updated=$(get_updated_cmd 'find . -iname "order*"')
assert_contains "find -iname: has knowledge output" "KNOWLEDGE ENTRIES" "$updated"

# ── find -wholename ──

updated=$(get_updated_cmd 'find . -wholename "*/models/*"')
assert_contains "find -wholename: has knowledge output" "KNOWLEDGE ENTRIES" "$updated"

# ── Fallback: content search when INDEX has no hits ──

# "redis" is in entry content (gotchas/order-cache.md) but not in any INDEX
updated=$(get_updated_cmd 'grep -rn "redis" app/')
assert_contains "fallback: content match prepends header" "=== KNOWLEDGE ENTRIES ===" "$updated"
assert_contains "fallback: finds entry by content" "order-cache.md" "$updated"

# "versioned" is in org entry content (api-contracts.md) but not in org INDEX
updated=$(get_updated_cmd 'grep -rn "versioned" lib/')
assert_contains "fallback: org content match" "api-contracts.md" "$updated"

# ── No matches: passthrough without prepend ──

out=$(run_hook 'grep -rn "zzz_nonexistent_term_zzz" app/')
if [[ -n "$out" ]]; then
  has_updated=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput // empty')
  assert_empty "no-match grep: no updatedInput" "$has_updated"
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')
  assert_eq "no-match grep: still allowed" "allow" "$decision"
else
  assert_empty "no-match grep: silent passthrough" "$out"
fi

out=$(run_hook 'rg "zzz_nonexistent_term_zzz" app/')
if [[ -n "$out" ]]; then
  has_updated=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput // empty')
  assert_empty "no-match rg: no updatedInput" "$has_updated"
else
  assert_empty "no-match rg: silent passthrough" "$out"
fi

out=$(run_hook 'find . -name "zzz_nonexistent_zzz"')
if [[ -n "$out" ]]; then
  has_updated=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput // empty')
  assert_empty "no-match find: no updatedInput" "$has_updated"
else
  assert_empty "no-match find: silent passthrough" "$out"
fi

# ── Layered lookup: org + project entries both surface ──

# "architecture" appears in entries at both org and project level
updated=$(get_updated_cmd 'grep -rn "architecture" .')
assert_contains "layered: project entries appear" "order" "$updated"
assert_contains "layered: org entries appear" "api" "$updated"

# ── Piped grep ──

updated=$(get_updated_cmd 'grep -rn "order" app/ | sort | uniq -c')
assert_contains "piped grep: knowledge still prepended" "KNOWLEDGE ENTRIES" "$updated"

# ── Grep piped into grep — term extraction picks up the last grep's pattern ──
# The hook extracts from the last grep in the pipe, which is `grep -v "test"`.
# Since "test" has no knowledge matches, this correctly passes through.

out=$(run_hook 'grep -rn "order" app/ | grep -v "test"')
if [[ -n "$out" ]]; then
  has_updated=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput // empty')
  assert_empty "piped grep chain: no match on filter term" "$has_updated"
else
  assert_empty "piped grep chain: passes through" "$out"
fi

# ── Empty pattern ──

result=$(run_hook 'grep -rn "" app/')
assert_empty "empty pattern: no crash, silent" "$result"

# ── Disabled hook ──

DISABLED_FILE="$SCRIPT_DIR/../.claude/hooks/.disabled_hooks"
echo "knowledge" > "$DISABLED_FILE"

result=$(run_hook 'grep -rn "order" app/')
assert_empty "disabled hook: produces no output" "$result"

rm -f "$DISABLED_FILE"

# ── Verify re-enabled after removing disable ──

updated=$(get_updated_cmd 'grep -rn "order" app/')
assert_contains "re-enabled: knowledge works again" "KNOWLEDGE ENTRIES" "$updated"

report
