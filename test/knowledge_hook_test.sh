#!/usr/bin/env bash
# Tests for knowledge-hook.sh
#
# knowledge-hook.sh is the user-facing output of the whole system. It runs
# after every Bash command, decides if it was a search, and if so, checks
# the INDEX for relevant knowledge entries. What it outputs is what the agent
# sees alongside search results. If it outputs garbage, the agent gets
# confused. If it outputs nothing when it should match, knowledge is invisible.
# If it fires on non-search commands, every ls and cat gets noise appended.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
HOOK="$SCRIPT_DIR/../.claude/hooks/knowledge-hook.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

echo "── knowledge-hook.sh ──"

export PROJECT_ROOT="$FIXTURES/project"
export ORG_DIR="$FIXTURES/org"
unset REPO_ROOT 2>/dev/null || true

# ── Non-search commands must be silent ──

# Every single Bash tool call hits this hook. ls, cat, mkdir, git, npm —
# all of them. If the hook produces output for non-search commands, every
# Bash call in every session gets knowledge noise appended to it.
result=$(echo '{"tool_input":{"command":"ls -la"}}' | "$HOOK" 2>&1)
assert_empty "ls produces no output" "$result"

result=$(echo '{"tool_input":{"command":"cat README.md"}}' | "$HOOK" 2>&1)
assert_empty "cat produces no output" "$result"

result=$(echo '{"tool_input":{"command":"git status"}}' | "$HOOK" 2>&1)
assert_empty "git produces no output" "$result"

# ── Search term matching against INDEX ──

# The INDEX has entries for "order" on the left side (file paths) and right
# side (entry names). A grep for "order" should match those lines and
# surface the knowledge.
result=$(echo '{"tool_input":{"command":"grep -rn \"order\" app/"}}' | "$HOOK" 2>&1)
assert_contains "grep for 'order' matches index entries" "order" "$result"
assert_contains "output has the knowledge header" "Knowledge Index Matches" "$result"

# A search for something that doesn't appear anywhere in the INDEX should
# produce nothing. False positives here would surface irrelevant knowledge
# and erode trust in the system.
result=$(echo '{"tool_input":{"command":"grep -rn \"zebra\" app/"}}' | "$HOOK" 2>&1)
assert_empty "no match for term not in index" "$result"

# ── Right-side matching (concept/category lookup) ──

# The INDEX right side contains entry paths like "architecture/actioncable-channels.md".
# Searching for "actioncable" should match via the entry name, even though
# "actioncable" doesn't appear in any file path on the left side. This is
# the two-vector lookup described in the roadmap.
result=$(echo '{"tool_input":{"command":"grep -rn \"actioncable\" app/"}}' | "$HOOK" 2>&1)
assert_contains "matches entry path on right side of index" "actioncable" "$result"

# Category names in entry paths should also match. Searching for "gotchas"
# should surface entries filed under the gotchas category.
result=$(echo '{"tool_input":{"command":"grep -rn \"gotchas\" app/"}}' | "$HOOK" 2>&1)
assert_contains "matches category name in entry path" "gotchas" "$result"

# ── Layered lookup (org + project) ──

# The org-level INDEX has entries that the project-level INDEX doesn't.
# If the hook only checks the project INDEX, org-level knowledge is
# invisible and the layering is broken.
result=$(echo '{"tool_input":{"command":"grep -rn \"api\" lib/"}}' | "$HOOK" 2>&1)
assert_contains "org-level index is searched" "api" "$result"

# When a search matches entries in both layers, both should appear in
# the output. The agent needs to see all relevant knowledge, not just
# whichever layer was checked first.
result=$(echo '{"tool_input":{"command":"grep -rn \"architecture\" ."}}' | "$HOOK" 2>&1)
assert_contains "project-level matches appear" "order" "$result"
assert_contains "org-level matches appear" "api" "$result"

# ── find triggers the hook too ──

# find is a search command. If it doesn't trigger the hook, anyone using
# find to locate files gets no knowledge augmentation.
result=$(echo '{"tool_input":{"command":"find . -name \"order*.rb\""}}' | "$HOOK" 2>&1)
assert_contains "find triggers knowledge lookup" "order" "$result"

# ── Malformed input ──

# If the hook input has no command field, the hook should exit silently.
# Crashing here would break every Bash tool call that has unusual input.
result=$(echo '{"tool_input":{}}' | "$HOOK" 2>&1)
assert_empty "missing command field produces no output" "$result"

result=$(echo '{}' | "$HOOK" 2>&1)
assert_empty "empty input produces no output" "$result"

report
