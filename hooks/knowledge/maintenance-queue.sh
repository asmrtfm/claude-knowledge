#!/usr/bin/env bash

# Short-circuit if disabled (this allows enabling|disabling mid-session)
if [[ -s "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi


# PostToolUse: logs file changes to MAINTENANCE_QUEUE with structured format.
# Scrubs entries whose files didn't actually change (mtime unchanged).


INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

# Don't queue knowledge maintenance for files inside .claude/
[[ "$FILE_PATH" != */.claude/* ]] || exit 0

TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

# Check mtime against pre-edit snapshot from the shared log
POST_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "NEW")
MTIME_LOG="${BASH_SOURCE[0]%/*}/mtime.log"

if [[ -f "$MTIME_LOG" ]]; then
  PRE_MTIME=$(grep "^${TOOL_USE_ID} " "$MTIME_LOG" 2>/dev/null | tail -1 | cut -d' ' -f2)
  # Remove consumed entry
  sed -i "/^${TOOL_USE_ID} /d" "$MTIME_LOG" 2>/dev/null

  # If mtime unchanged, file didn't actually change — skip
  if [[ -n "$PRE_MTIME" && "$PRE_MTIME" == "$POST_MTIME" && "$PRE_MTIME" != "NEW" ]]; then
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
