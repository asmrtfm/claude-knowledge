#!/usr/bin/env bash
shopt -s globstar
trap 'shopt -u globstar' EXIT
# Searches the knowledge base for entries relevant to the given search terms.
# Usage: query-knowledge.sh <knowledge_dir> <search_terms>

KNOWLEDGE_DIR="$1"
SEARCH_TERMS="$2"
ENTRIES_DIR="$KNOWLEDGE_DIR/entries"

[[ -z "$SEARCH_TERMS" ]] && exit 0
[[ -d "$ENTRIES_DIR" ]] || exit 0

# Tokenize search terms for multi-signal matching
IFS=' ._-/' read -ra TOKENS <<< "$SEARCH_TERMS"

for entry in "$ENTRIES_DIR"/*.md "$ENTRIES_DIR"/**/*.md; do
  [[ -f "$entry" ]] || continue

  SCORE=0
  TOTAL=${#TOKENS[@]}

  for token in "${TOKENS[@]}"; do
    [[ -z "$token" || ${#token} -lt 2 ]] && continue
    # Case-insensitive match against entry content
    if grep -qil "$token" "$entry" 2>/dev/null; then
      ((SCORE++))
    fi
  done

  # Require at least one token match
  [[ $SCORE -eq 0 ]] && continue

  # Extract entry metadata
  TAGS=$(grep -oP '(?<=tags:\s).*' "$entry" 2>/dev/null | head -1)

  echo "• ${entry#"$ENTRIES_DIR"/} [$SCORE/$TOTAL tokens matched]"
  [[ -n "$TAGS" ]] && echo "  tags: $TAGS"
  echo ""
done
