#!/usr/bin/env bash
# Auto-fires on maintain mode invocation.
# Sets up the maintenance log file and exports its path.

# Resolve from two levels up: skills/knowledge/ -> hooks/knowledge/lib/
. "${BASH_SOURCE[0]%/*}/../../hooks/knowledge/lib/resolve-env.sh"
_set_repo_root

KNOWLEDGE_DIR="${REPO_ROOT:-$PROJECT_ROOT}/.claude/knowledge"

STAMP=$(date '+%Y%m%d/%H%M%S')
SESSION="${CLAUDE_SESSION_ID:-${SESSION_ID:-unknown}}"
LOG_FILE="$KNOWLEDGE_DIR/maintenance/${STAMP}_${SESSION}.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

export KNOWLEDGE_MAINTENANCE_LOG="$LOG_FILE"
echo "$LOG_FILE"
