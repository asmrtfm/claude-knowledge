#!/usr/bin/env bash

# Resolves REPO_ROOT, REPO_NAME, ORG_DIR, and ORG_NAME from the filesystem.
# No-ops if the vars are already populated.

# Loads env vars from .claude/settings.json and .claude/settings.local.json.
# Only sets vars that are not already in the environment.
_load_settings_env() {
  local settings_dir="$(realpath "${1:-$(pwd)}" 2>/dev/null)/.claude" || return 1
  [[ -d "$settings_dir" ]] || return 0
  for f in "$settings_dir/settings.json" "$settings_dir/settings.local.json"; do
    [[ -f "$f" ]] || continue
    local keys
    keys=$(jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$f" 2>/dev/null) || continue
    while IFS='=' read -r key val; do
      # Don't overwrite existing env vars
      [[ -n "$key" ]] || continue
      [[ -n "${!key}" ]] || export "$key=$val"
    done <<< "$keys"
  done
}

_set_repo_root() {
  [[ -z $REPO_ROOT ]] || return 0
  local Dir="$(realpath "${1:-$(pwd)}")"
  [[ -d "$Dir" ]] || return 1
  while [[ "${Dir}/" != +(\/) ]]; do
    if [[ -d "${Dir}/.git" ]]; then
      export REPO_ROOT="$Dir"
      export REPO_NAME="${Dir##*\/}"
      return 0
    fi
    Dir="${Dir%\/*}"
  done
  return 1
}

_set_project_root() {
  if ! _set_repo_root "${@}"; then
    [[ -z $PROJECT_ROOT ]] || return 0
    export PROJECT_ROOT="$(realpath "${1:-$(pwd)}")"
  fi
}

_set_org_dir() {
  [[ -z $ORG_DIR ]] || return 0
  [[ -d "$REPO_ROOT" ]] || _set_repo_root "${@}" || return 1
  local maybe_org="${REPO_ROOT%\/*}"
  if [[ "${maybe_org##*\/}" == $(git remote get-url origin | awk -F'[:/]' '{print $(NF-1)}') ]]; then
    export ORG_DIR="$maybe_org"
    export ORG_NAME="${maybe_org##*\/}"
  fi
}


# Resolves knowledge directories.
# Outputs one or two paths — project/repo level first, then org level (if already configured).
_resolve_knowledge_dirs() {
  _set_project_root "${@}"
  _load_settings_env "${@}"
  for d in "${ORG_DIR:-}" "$(realpath "${REPO_ROOT:-${PROJECT_ROOT:=${1:-$(pwd)}}}" 2>/dev/null)"; do
    for candidate in '.claude' 'docs'; do
      [[ ! -d "${d}/${candidate}/knowledge" ]] || echo "${d}/${candidate}/knowledge"
    done
  done
}

export -f _load_settings_env
export -f _set_repo_root
export -f _set_org_dir
export -f _set_project_root
export -f _resolve_knowledge_dirs
