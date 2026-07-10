#!/usr/bin/env bash
# Tests for knowledge.sh — the PreToolUse search interception hook.
# Scope: recursive grep, rg, find.

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "$SCRIPT_DIR/helpers/assert.sh"
HOOK="$SCRIPT_DIR/../.claude/hooks/knowledge/knowledge.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

export REPO_ROOT="$FIXTURES/project"
export ORG_DIR="$FIXTURES/org"

echo "── knowledge.sh ──"

# Feed a command through the hook, return the extracted query
extract_query() {
  local json out new_cmd
  json=$(jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}')
  out=$(printf '%s' "$json" | "$HOOK" 2>/dev/null) || true
  [[ -n "$out" ]] || return 0
  new_cmd=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // ""')
  [[ -n "$new_cmd" ]] || return 0
  printf '%s' "$new_cmd" | sed -n 's/.*grep -liIRs "\([^"]*\)".*/\1/p'
}

# ast-grep must not be intercepted
result=$(extract_query 'ast-grep -p "console.log($$$)" src/')
assert_empty "ast-grep skipped" "$result"

# non-recursive grep must not be intercepted
result=$(extract_query 'grep -n "pattern" file.txt')
assert_empty "non-recursive grep skipped" "$result"

# recursive grep with stacked flags — extracts the pattern through the noise
result=$(extract_query 'grep -rni --color=never --exclude-dir=node_modules "ActionCable" app/')
assert_eq "grep -rni stacked flags" "(ActionCable)" "$result"

# rg with stacked flags — same extraction path, different prefix
result=$(extract_query 'rg -i -w --hidden --json "order_status" app/models/')
assert_eq "rg stacked flags" "(order_status)" "$result"

# grep piped to another command — extraction still works on the grep portion
result=$(extract_query 'grep -rn "TODO" app/ | sort | uniq -c')
assert_eq "grep piped" "(TODO)" "$result"

# find -wholename
result=$(extract_query 'find . -wholename "*/models/*"')
assert_eq "find -wholename" "(/models/)" "$result"

# find -iname — case-insensitive variant
result=$(extract_query 'find . -iname "readme*"')
assert_eq "find -iname" "(readme)" "$result"

# empty pattern — no crash, no output
result=$(extract_query 'grep -rn "" app/')
assert_empty "empty pattern" "$result"

report
