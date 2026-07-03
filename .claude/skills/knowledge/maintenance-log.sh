#!/usr/bin/env bash
# Auto-fires on maintain mode invocation.
# Sets up the maintenance log file and exports its path.

KNOWLEDGE_DIR=""
if [[ -n "$REPO_ROOT" ]]; then
  KNOWLEDGE_DIR="$REPO_ROOT/.claude/knowledge"
elif [[ -n "$PROJECT_ROOT" ]]; then
  KNOWLEDGE_DIR="$PROJECT_ROOT/.claude/knowledge"
fi

[[ -z "$KNOWLEDGE_DIR" ]] && exit 0

STAMP=$(date '+%Y%m%d/%H%M%S')
SESSION="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
LOG_FILE="$KNOWLEDGE_DIR/maintenance/${STAMP}_${SESSION}.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

export KNOWLEDGE_MAINTENANCE_LOG="$LOG_FILE"
echo "$LOG_FILE"
