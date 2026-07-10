#!/usr/bin/env bash
# Extracts the search query/pattern from grep, find, rg, and related commands.
# Reads the full command from stdin, outputs the extracted terms to stdout.

INPUT=$(cat)

# grep-family: extract the search pattern
if echo "$INPUT" | grep -qE '\b(grep|egrep|fgrep|rg|ag|ack)\b'; then
  # Quoted pattern (single or double quotes)
  PATTERN=$(echo "$INPUT" | grep -oP "(?<=[\"'])[^\"']+(?=[\"'])" | head -1)

  if [[ -z "$PATTERN" ]]; then
    # Unquoted: strip the command and flags, take first positional arg
    PATTERN=$(echo "$INPUT" | sed -E 's/.*\b(grep|egrep|fgrep|rg|ag|ack)\b//' \
      | tr '|' ' ' \
      | sed -E 's/\s+-[a-zA-Z]+//g' \
      | awk '{print $1}')
  fi

  # Strip regex metacharacters to get plain search terms
  echo "$PATTERN" | sed -E 's/[\\^$.*+?(){\[|]/ /g' | xargs
  exit 0
fi

# find-family: extract -name/-iname or fd's first positional arg
if echo "$INPUT" | grep -qE '\b(find|fd)\b'; then
  # Extract the argument after -name or -iname
  PATTERN=$(echo "$INPUT" | sed -nE 's/.*-i?name[[:space:]]+["\x27]?([^"\x27[:space:]]+)["\x27]?.*/\1/p' | head -1)

  if [[ -z "$PATTERN" ]]; then
    # fd uses first arg as pattern
    PATTERN=$(echo "$INPUT" | sed -nE 's/.*\bfd[[:space:]]+["\x27]?([^"\x27[:space:]]+).*/\1/p' | head -1)
  fi

  # Strip glob metacharacters
  echo "$PATTERN" | sed -E 's/[*?]/ /g' | xargs
  exit 0
fi
