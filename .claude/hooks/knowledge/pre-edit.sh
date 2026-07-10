#!/usr/bin/env bash

if [[ -f "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi


# PreToolUse: records file mtime before edit so the PostToolUse hook
# can detect whether the file actually changed.

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" ]] && exit 0

TOOL_USE_ID=$(echo "$INPUT" | jq -r '.tool_use_id // empty' 2>/dev/null)
[[ -z "$TOOL_USE_ID" ]] && exit 0

MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "NEW")

# Store pre-edit mtime keyed by tool_use_id
mkdir -p /tmp/knowledge-hooks
echo "$MTIME" > "/tmp/knowledge-hooks/${TOOL_USE_ID}.mtime"
