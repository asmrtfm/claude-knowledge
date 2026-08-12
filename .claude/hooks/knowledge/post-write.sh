#!/usr/bin/env bash

# Short-circuit if disabled (this allows enabling|disabling mid-session)
if [[ -s "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi

# PostToolUse (Write): keeps track of which sessions created knowledge entries - their transcripts are likely of high value.
# Writes relative path to the entry into a log file: knowledge/write-logs/<session_id>.list

INPUT=$(cat)

FILE_PATH=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")

# Only care about knowledge entry writes
[[ "$FILE_PATH" == *knowledge/entries/* ]] || exit 0

CLAUDE_DIR="$(nearest -d .claude --from "${BASH_SOURCE[0]%\/*}")"

[[ -n $CLAUDE_SESSION_ID ]] || CLAUDE_SESSION_ID=$(jq -r '.session_id // .sessionId // ""' <<<"$INPUT")
[[ -n $KNOW_WRITES ]] || KNOW_WRITES="${CLAUDE_DIR}/knowledge/write-logs"
mkdir -p "$KNOW_WRITES"

entry="$(realpath "$FILE_PATH")"
[[ "$entry" != "${CLAUDE_DIR}/"*"${FILE_PATH##*\/}" ]] || entry="${FILE_PATH#*${CLAUDE_DIR}}"

touch "${KNOW_WRITES}/${CLAUDE_SESSION_ID}.list"
if ! grep -qs "$entry" "${KNOW_WRITES}/${CLAUDE_SESSION_ID}.list" >/dev/null; then
  echo "$entry" >> "${KNOW_WRITES}/${CLAUDE_SESSION_ID}.list"
fi
