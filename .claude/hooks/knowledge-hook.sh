#!/usr/bin/env bash
# PostToolUse on Bash: intercepts search commands and augments results
# with matching entries from the knowledge INDEX.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Only activate on search operations
SEARCH_CMD_PATTERN='\b(grep|egrep|fgrep|rg|ag|ack|find|fd|locate)\b'
echo "$COMMAND" | grep -qE "$SEARCH_CMD_PATTERN" || exit 0

# Extract search terms from the command
SEARCH_TERMS=$("$SCRIPT_DIR/lib/parse-search.sh" <<< "$COMMAND")
[[ -z "$SEARCH_TERMS" ]] && exit 0

# Resolve knowledge directories and search each INDEX
KNOWLEDGE_DIRS=$("$SCRIPT_DIR/lib/resolve-dirs.sh" 2>/dev/null)
[[ -z "$KNOWLEDGE_DIRS" ]] && exit 0

MATCHES=""

while IFS= read -r KDIR; do
  INDEX_FILE="$KDIR/INDEX.md"
  [[ -f "$INDEX_FILE" ]] || continue

  # Search the index for matches against the search terms
  while IFS= read -r LINE; do
    # Skip comments and empty lines
    [[ "$LINE" =~ ^#.*$ || -z "$LINE" ]] && continue

    echo "$LINE" | grep -qi "$SEARCH_TERMS" || continue

    if [[ -n "$MATCHES" ]]; then
      MATCHES="$MATCHES"$'\n'
    fi
    MATCHES="$MATCHES• $LINE"
    MATCHES="$MATCHES"$'\n'"  ($(basename "$(dirname "$KDIR")")/$(basename "$KDIR"))"
  done < "$INDEX_FILE"
done <<< "$KNOWLEDGE_DIRS"

if [[ -n "$MATCHES" ]]; then
  echo ""
  echo "━━━ Knowledge Index Matches ━━━"
  echo "$MATCHES"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi
