#!/usr/bin/env bash

echo "[$(date)] ${BASH_SOURCE[0]}" >> ~/.claude/hooks/run.log

# if [[ -n $CLAUDE_HOOKS ]]; then
#   [[ "$CLAUDE_HOOKS" == *memory_gate* ]] || exit 0
# fi
. "${GLOBAL_CLAUDE_DIR}/hooks/lib/share/utils" --all

_hook_enabled "${BASH_SOURCE[0]}" || exit 0

# . "${GLOBAL_CLAUDE_DIR}/hooks/lib/share/common" --empty --all

. "${GLOBAL_CLAUDE_DIR}/hooks/lib/share/pre_tool_use" --empty 'file_path'

# Anthropic's theme has thus far been to build the most token-hungry version of whatever the latest inovation in harness engineering is.
# Looks like memory is no different because claude not only writes absurd memories for damn near everything you say to it, but
# then it never actually applies them where it might have been useful.
#
# It's just their latest fucking token incenerator.

# Force a permission prompt before Write|Update|Edit touches the auto-memory directory.
# Matches any file under a project's memory dir.
Input=$(cat)
# FILE_PATH=$(echo "$Input" | jq -r '.tool_input.file_path // empty')
file_path=$(_file_path)

_log_file_ "${BASH_SOURCE[0]}"

case "$file_path" in
  "${GLOBAL_CLAUDE_DIR}/projects/-"*)
    jq -n --arg f "$file_path" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: ("Writing/editing auto-memory file (" + $f + ") requires explicit user permission.")
      }
    }' ;;
  *) exit 0
esac
