#!/usr/bin/env bash
# Resolves knowledge directories from environment variables.
# Outputs one or two paths — project/repo level first, then org level.
# Consumers read lines and filter for directories that exist.

# Project or repo level
if [[ -n "$REPO_ROOT" ]]; then
  echo "$REPO_ROOT/.claude/knowledge"
elif [[ -n "$PROJECT_ROOT" ]]; then
  echo "$PROJECT_ROOT/.claude/knowledge"
fi

# Org level
if [[ -n "$ORG_DIR" ]]; then
  echo "$ORG_DIR/.claude/knowledge"
fi
