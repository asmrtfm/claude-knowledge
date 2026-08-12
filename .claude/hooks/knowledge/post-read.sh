#!/usr/bin/env bash

# Short-circuit if disabled (this allows enabling|disabling mid-session)
if [[ -s "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi

# PostToolUse (Read): tracks which knowledge entries have been read during this session.
# Writes entry names to a session-scoped log so that pre-search.sh can skip
# surfacing entries the model has already seen.

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -n "$FILE_PATH" ]] || exit 0

# Only care about knowledge entry reads
[[ "$FILE_PATH" == *knowledge/entries/* ]] || exit 0

[[ -n $CLAUDE_SESSION_ID ]] || CLAUDE_SESSION_ID=$(jq -r '.session_id // .sessionId // ""' <<<"$INPUT")
CLAUDE_SESSION_CACHE="${CLAUDE_LOCAL_CACHE:-$(nearest -d .claude --from "${BASH_SOURCE[0]%\/*}")/cache}"
[[ "$CLAUDE_SESSION_CACHE" == *"$CLAUDE_SESSION_ID"* ]] || CLAUDE_SESSION_CACHE="${CLAUDE_SESSION_CACHE}/${CLAUDE_SESSION_ID}"
mkdir -p "$CLAUDE_SESSION_CACHE"

# Extract the entry's relative path under entries/ (e.g. "architecture/sidebar.md")
entry="$(realpath "$FILE_PATH")"
[[ "$entry" == "$FILE_PATH" ]] || entry="$FILE_PATH"

# Append to the session's read log (deduplicated on write)
touch "${CLAUDE_SESSION_CACHE}/reads.log"
{ cat "${CLAUDE_SESSION_CACHE}/reads.log" && echo "$entry"; } | awk '!a[$0]++' | tee "${CLAUDE_SESSION_CACHE}/reads.log" >/dev/null
