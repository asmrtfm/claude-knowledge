#!/usr/bin/env bash

if [[ -f "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi


# PostToolUse: logs file changes to MAINTENANCE_QUEUE with structured format.
# Scrubs entries whose files didn't actually change (mtime unchanged).


INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

# Don't queue edits to knowledge files themselves
[[ "$FILE_PATH" != */.claude/knowledge/* ]] || exit 0

TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

# Check mtime against pre-edit snapshot
POST_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "NEW")
PRE_MTIME_FILE="/tmp/knowledge-hooks/${TOOL_USE_ID}.mtime"

if [[ -f "$PRE_MTIME_FILE" ]]; then
  PRE_MTIME=$(cat "$PRE_MTIME_FILE")
  rm -f "$PRE_MTIME_FILE"

  # If mtime unchanged, file didn't actually change — skip
  if [[ "$PRE_MTIME" == "$POST_MTIME" && "$PRE_MTIME" != "NEW" ]]; then
    exit 0
  fi
fi

MTIME_STAMP=$(date -d "@${POST_MTIME}" '+%Y%m%d_%H%M%S' 2>/dev/null || echo "$POST_MTIME")

. "${BASH_SOURCE[0]%/*}/lib/resolve-env.sh"
_set_repo_root

QUEUE_FILE="${REPO_ROOT:-$PROJECT_ROOT}/.claude/knowledge/MAINTENANCE_QUEUE"

[[ -z "$QUEUE_FILE" || ! -d "$(dirname "$QUEUE_FILE")" ]] && exit 0

# Deduplicate on file path within the same queue cycle
if grep -qF "$FILE_PATH" "$QUEUE_FILE" 2>/dev/null; then
  exit 0
fi

# Format: <tool_use_id> <YYYYMMDD_HHMMSS mtime> <session_id> <tool_name> <filepath>
echo "${TOOL_USE_ID} ${MTIME_STAMP} ${SESSION_ID} ${TOOL_NAME} ${FILE_PATH}" >> "$QUEUE_FILE"
