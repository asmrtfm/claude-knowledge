#!/usr/bin/env bash
# Tests for resolve-dirs.sh
#
# resolve-dirs.sh decides which knowledge directories exist and should be
# searched. Every other part of the system depends on it returning the right
# paths in the right order. If it returns the wrong directory, knowledge
# lookups hit the wrong INDEX. If it returns nothing, the entire system is off.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
RESOLVE="$SCRIPT_DIR/../.claude/hooks/lib/resolve-dirs.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

# We need a clean directory with no conventional knowledge dirs for tests
# that should find nothing locally.
CLEAN_DIR=$(mktemp -d)

echo "── resolve-dirs.sh ──"

# ── Env var resolution ──

# PROJECT_ROOT is the primary way non-git projects tell the system where
# knowledge lives. This is the most common configuration path.
export PROJECT_ROOT="$FIXTURES/project"
unset REPO_ROOT ORG_DIR 2>/dev/null || true
result=$(cd "$CLEAN_DIR" && "$RESOLVE")
assert_eq "PROJECT_ROOT resolves to project knowledge dir" "$FIXTURES/project/.claude/knowledge" "$result"

# Git-based projects use REPO_ROOT instead of PROJECT_ROOT. Both need to work
# because the system is designed to operate with or without git.
unset PROJECT_ROOT ORG_DIR 2>/dev/null || true
export REPO_ROOT="$FIXTURES/project"
result=$(cd "$CLEAN_DIR" && "$RESOLVE")
assert_eq "REPO_ROOT resolves to repo knowledge dir" "$FIXTURES/project/.claude/knowledge" "$result"

# When both are set (e.g. a git repo inside a broader project), REPO_ROOT
# is more specific and should take precedence. Without this, the system
# could check the wrong knowledge directory.
export REPO_ROOT="$FIXTURES/project" PROJECT_ROOT="/somewhere/else"
unset ORG_DIR 2>/dev/null || true
result=$(cd "$CLEAN_DIR" && "$RESOLVE")
assert_eq "REPO_ROOT takes precedence over PROJECT_ROOT" "$FIXTURES/project/.claude/knowledge" "$result"

# ── Layered lookup ──

# The whole point of layered knowledge is that both org and project dirs are
# returned so both INDEXes get searched. If only one comes back, half the
# knowledge base is invisible.
unset REPO_ROOT 2>/dev/null || true
export PROJECT_ROOT="$FIXTURES/project" ORG_DIR="$FIXTURES/org"
result=$(cd "$CLEAN_DIR" && "$RESOLVE")
first=$(echo "$result" | head -1)
second=$(echo "$result" | tail -1)
lines=$(echo "$result" | wc -l)
assert_eq "returns two dirs when both project and org are set" "2" "$lines"
# Project is more specific than org. Consumers may rely on this ordering
# to prioritize project-level knowledge over org-level.
assert_eq "project dir comes first" "$FIXTURES/project/.claude/knowledge" "$first"
assert_eq "org dir comes second" "$FIXTURES/org/.claude/knowledge" "$second"

# Org-level alone (no project/repo set) should still return the org dir.
# This covers the case where someone is working at the org level, not in
# a specific project. Run from a clean dir so fallback discovery doesn't
# find a local .claude/knowledge.
unset PROJECT_ROOT REPO_ROOT 2>/dev/null || true
export ORG_DIR="$FIXTURES/org"
result=$(cd "$CLEAN_DIR" && "$RESOLVE")
assert_eq "org dir alone" "$FIXTURES/org/.claude/knowledge" "$result"

# ── Fallback discovery ──

# Not every project will have env vars configured in settings.json. The
# system should still work if someone just has the conventional directory
# structure in place.
unset PROJECT_ROOT REPO_ROOT ORG_DIR 2>/dev/null || true
result=$(cd "$FIXTURES/project" && "$RESOLVE")
assert_eq "discovers .claude/knowledge by convention" "$FIXTURES/project/.claude/knowledge" "$result"

# docs/knowledge is a secondary convention for projects that keep knowledge
# alongside other documentation.
unset PROJECT_ROOT REPO_ROOT ORG_DIR 2>/dev/null || true
docs_tmp=$(mktemp -d)
mkdir -p "$docs_tmp/docs/knowledge"
result=$(cd "$docs_tmp" && "$RESOLVE")
assert_eq "discovers docs/knowledge by convention" "$docs_tmp/docs/knowledge" "$result"
rm -rf "$docs_tmp"

# A bare knowledge/ directory is the simplest possible setup.
unset PROJECT_ROOT REPO_ROOT ORG_DIR 2>/dev/null || true
bare_tmp=$(mktemp -d)
mkdir -p "$bare_tmp/knowledge"
result=$(cd "$bare_tmp" && "$RESOLVE")
assert_eq "discovers bare knowledge/ by convention" "$bare_tmp/knowledge" "$result"
rm -rf "$bare_tmp"

# When multiple conventional directories exist, .claude/knowledge wins
# because it's the most tightly scoped to the claude workflow. Without
# defined precedence, the system could pick docs/knowledge over
# .claude/knowledge and miss project-specific entries.
unset PROJECT_ROOT REPO_ROOT ORG_DIR 2>/dev/null || true
multi_tmp=$(mktemp -d)
mkdir -p "$multi_tmp/.claude/knowledge" "$multi_tmp/docs/knowledge"
result=$(cd "$multi_tmp" && "$RESOLVE")
assert_eq ".claude/knowledge wins over docs/knowledge" "$multi_tmp/.claude/knowledge" "$result"
rm -rf "$multi_tmp"

# If there's nothing to find — no env vars, no conventional directories —
# the script should exit cleanly with no output. Crashing or outputting
# garbage here would break every downstream consumer.
unset PROJECT_ROOT REPO_ROOT ORG_DIR 2>/dev/null || true
result=$(cd "$CLEAN_DIR" && "$RESOLVE")
assert_empty "no dirs found, no output" "$result"

# Clean up
rm -rf "$CLEAN_DIR"

report
