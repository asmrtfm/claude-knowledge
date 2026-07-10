#!/usr/bin/env bash

# Resolves REPO_ROOT, REPO_NAME, ORG_DIR, and ORG_NAME from the filesystem.
# No-ops if the vars are already populated.

# Loads env vars from .claude/settings.json and .claude/settings.local.json.
# Only sets vars that are not already in the environment.
_load_settings_env() {
  local root="${1:-$(pwd)}"
  local settings_dir="$root/.claude"
  [[ -d "$settings_dir" ]] || return 0
  for f in "$settings_dir/settings.json" "$settings_dir/settings.local.json"; do
    [[ -f "$f" ]] || continue
    local keys
    keys=$(jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$f" 2>/dev/null) || continue
    while IFS='=' read -r key val; do
      [[ -n "$key" ]] || continue
      # Don't overwrite existing env vars
      [[ -z "${!key}" ]] && export "$key=$val"
    done <<< "$keys"
  done
}

_set_repo_root() {
  [[ -z $REPO_ROOT ]] || return 0
  local Dir="$(realpath "${1:-$(pwd)}")"
  [[ -d "$Dir" ]] || return 1
  while [[ "${Dir}/" != "/" ]]; do
    if [[ -d "${Dir}/.git" ]]; then
      export REPO_ROOT="$Dir"
      export REPO_NAME="${Dir##*\/}"
      return 0
    fi
    Dir="${Dir%\/*}"
  done
  return 1
}

_set_org_dir() {
  [[ -z $ORG_DIR ]] || return 0
  [[ -d "$REPO_ROOT" ]] || _set_repo_root || return 1
  local maybe_org="${REPO_ROOT%\/*}"
  if [[ "${maybe_org##*\/}" == $(git remote get-url origin | awk -F'[:/]' '{print $(NF-1)}') ]]; then
    export ORG_DIR="$maybe_org"
    export ORG_NAME="${maybe_org##*\/}"
  fi
}


# Resolves knowledge directories.
# Outputs one or two paths — project/repo level first, then org level.
_resolve_knowledge_dirs() {
  local found_project=false

  if [[ -d "${REPO_ROOT:=$(pwd)}/.claude/knowledge" ]]; then
    echo "$REPO_ROOT/.claude/knowledge"
    found_project=true
  elif [[ -d "${PROJECT_ROOT:=$(pwd)}/.claude/knowledge" ]]; then
    echo "$PROJECT_ROOT/.claude/knowledge"
    found_project=true
  fi

  if [[ "$found_project" == false ]]; then
    for candidate in .claude/knowledge docs/knowledge knowledge; do
      if [[ -d "$candidate" ]]; then
        echo "$(pwd)/$candidate"
        break
      fi
    done
  fi

  if [[ -d "$ORG_DIR" && -d "${ORG_DIR}/.claude/knowledge" ]]; then
    echo "$ORG_DIR/.claude/knowledge"
  fi
}

export -f _load_settings_env
export -f _set_repo_root
export -f _set_org_dir
export -f _resolve_knowledge_dirs
