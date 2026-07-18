#!/usr/bin/env bash

# Installs the knowledge system into a target project or org workspace.
# Usage: install.sh [--repo | --org | --update] [target_dir]
#        Defaults to current directory if no target given.


# ---------------------------
# Absolute path to this script
SELF="$(realpath "${BASH_SOURCE[0]}")"
# Directory containing this script (the claude-knowledge source repo)
SOURCE_DIR="${SELF%\/*}"

[[ -d "${SOURCE_DIR}/bin" ]] || exit 3
# For helpers such as safe_copy and prompt_value
PATH="${SOURCE_DIR}/bin:${PATH}"


# ---------------------------
# Install mode: "repo", "org", or "project" — auto-detected if not given
declare -g MODE=""
# --update: skip copying hooks/skills/dirs, only run migrations + settings
UPDATE_ONLY=false
# --hooks-only: reinstall just hook scripts and settings, then exit
HOOKS_ONLY=false
# Target directory to install into — defaults to pwd
declare -g TARGET=""
declare -g SETTINGS=""

# ---------------------------
. "$SOURCE_DIR/.claude/hooks/knowledge/lib/resolve-env.sh"

# Parse input args
for ((a=1;a<=$#;a++)); do
  case "${!a}" in
  --org) MODE="org"; _set_org_dir ;;
  --repo) MODE="repo"; _set_repo_root ;;
  --update) UPDATE_ONLY=true; _set_project_root ;;
  --hooks-only) HOOKS_ONLY=true; _set_project_root ;;
  *) [[ -d "${!a}" ]] && TARGET="${!a}" || {
    echo "[ERROR] Invalid argument: '${!a}'" >&2; exit 1; }
  esac
done

# Resolve to absolute path, default to current directory
declare -g TARGET="$(realpath "${TARGET:-.}")"

# Bail if target doesn't exist
[[ -d "$TARGET" ]] || { echo "Target directory does not exist: $TARGET"; exit 1; }



# ─────────────────────────────────────────────────────────────────────────────────
# Permissions for skill scripts
declare -g settings_permissions_allow='["Bash(*/.claude/skills/knowledge/load-env.sh)","Bash(*/.claude/skills/knowledge/skills/maintain/maintenance-log.sh)","Bash(*/.claude/skills/knowledge/skills/maintain/audit.sh)","Bash(knowledge *)"]'

# JSON block defining which hooks fire on which Claude tool events
_settings_hooks() { cat <<'HOOKS'
{ "PreToolUse": [
  { "matcher": "Bash", "hooks": [{"type": "command", "command": "\"${REPO_ROOT:-${PROJECT_ROOT}}\"/.claude/hooks/knowledge/pre-search.sh", "shell": "bash"}] },
  { "matcher": "Edit|Write|NotebookEdit", "hooks": [{"type": "command", "command": "\"${REPO_ROOT:-${PROJECT_ROOT}}\"/.claude/hooks/knowledge/pre-edit.sh", "shell": "bash"}] }
], "PostToolUse": [
  { "matcher": "Edit|Write|NotebookEdit", "hooks": [{"type": "command", "command": "\"${REPO_ROOT:-${PROJECT_ROOT}}\"/.claude/hooks/knowledge/maintenance-queue.sh", "shell": "bash"}] }
] }
HOOKS
}



# ─────────────────────────────────────────────────────────────────────────────────
_install_hooks() {
  # Create hook directory tree and copy each hook script
  mkdir -p "$TARGET/.claude/hooks/knowledge/lib"
  for hook in pre-search.sh pre-edit.sh maintenance-queue.sh; do
    safe_copy -v "$SOURCE_DIR/.claude/hooks/knowledge/$hook" "$TARGET/.claude/hooks/knowledge/$hook"
    chmod +x "$TARGET/.claude/hooks/knowledge/$hook"
  done
  # Copy shared lib scripts (sourced by hooks, not executed directly)
  for lib in resolve-env.sh query-knowledge.sh; do
    safe_copy -v "$SOURCE_DIR/.claude/hooks/knowledge/lib/$lib" "$TARGET/.claude/hooks/knowledge/lib/$lib"
  done
  touch "$TARGET/.claude/hooks/.disabled_hooks"
}


# ─────────────────────────────────────────────────────────────────────────────────
_ask_settings() {
  # Let user choose where hooks go: versioned or git-ignored
  { echo ""
    echo "Where should hooks be configured?"
    echo "    1) settings.json        — versioned, shared with collaborators"
    echo "    2) settings.local.json  — personal, git-ignored"
    echo ""
  } >&2
  read -rep " Install hooks into [1|2] (default: 2): " settings
  case "$settings" in
  1) SETTINGS="$TARGET/.claude/settings.json" ;;
  *)
    if [[ -d "$TARGET/.git" ]]; then
      if ! grep -qs -E "(claude/)?settings.local.json" "$TARGET/.gitignore" 2>/dev/null; then
        printf '\n\n%s\n' ".claude/settings.local.json is missing from .gitignore"
        read -rep "Append '.claude/settings.local.json' to .gitignore?  (y|n) " append_ignore
        if [[ "${append_ignore,,}" == y?(es) ]]; then
          echo '.claude/settings.local.json' >> "$TARGET/.gitignore"
        fi
      fi
    fi
    SETTINGS="$TARGET/.claude/settings.local.json"
  esac
}

_tell_configured_hooks() { printf '\n\n%s\n\n' "Hooks configured in .claude/${SETTINGS##*\/}"; }


# ─────────────────────────────────────────────────────────────────────────────────
# ── Hooks-only reinstall ──
# Fast path: only copy hook scripts and merge settings, then exit.
# Used when hooks need updating but the rest of the install is fine.

if [[ "$HOOKS_ONLY" == true ]]; then
  echo ""
  echo "Reinstalling hooks in: $TARGET"
  echo ""
  _install_hooks
  _ask_settings
  _tell_configured_hooks
  echo ""
  echo "Done."
  exit 0
fi



# ─────────────────────────────────────────────────────────────────────────────────
_install_skill() {
  if [[ "$TARGET" == "$SOURCE_DIR" ]]; then
    echo "[ERROR] TARGET == SOURCE_DIR..." >&2
    exit 1
  fi
  mkdir -p "$TARGET/.claude/skills"
  if [[ -d "$TARGET/.claude/skills/knowledge" ]]; then
    echo "Knowledge Skill directory already exists: '$TARGET/.claude/skills/knowledge'"
    read -rep "Create backup? [y/N]: " answ
    if [[ "${answ,,}" == y?(es) ]]; then
      local bak="$TARGET/.claude/.skills_-_knowledge.bak_$(date '+%s')"
      mv -v "$TARGET/.claude/skills/knowledge" "$bak" || { echo "[ERROR] Failed to create backup..." >&2; exit 2; }
      echo "Backup created."
    fi
    rm -rf "$TARGET/.claude/skills/knowledge"
  fi
  command cp -r "$SOURCE_DIR/.claude/skills/knowledge" "$TARGET/.claude/skills/knowledge"
  find "$TARGET/.claude/skills/knowledge" -type f -name "*.sh" -exec chmod +x '{}' \;
  echo "  skills installed"
  tree "$TARGET/.claude/skills/knowledge"
}


# ─────────────────────────────────────────────────────────────────────────────────
# ── Create knowledge directory structure ──
#
_establish_knowledge_dir() {
  mkdir -p "$TARGET/.claude/knowledge/entries"/{architecture,domain,gotchas,relationships,workflows}
  # Historical entries (archived/obsolete), Maintenance session logs, and Inspection logs.
  mkdir -p "$TARGET/.claude/knowledge"/{historical,maintenance,inspections}
  
  # Create INDEX.md and MAINTENANCE_QUEUE it they don't yet exist.
  for f in {INDEX.md,MAINTENANCE_QUEUE}; do
    [[ -f "$TARGET/.claude/knowledge/${f}" ]] || touch "$TARGET/.claude/knowledge/${f}"
  done
  
  # Migration: rename old FILE_INDEX.md to INDEX.md if needed
  if [[ -f "$TARGET/.claude/knowledge/FILE_INDEX.md" ]]; then
    if [[ ! -s "$TARGET/.claude/knowledge/INDEX.md" ]]; then
      # if INDEX does not yet exist or it does but is empty
      mv -v "$TARGET/.claude/knowledge/FILE_INDEX.md" "$TARGET/.claude/knowledge/INDEX.md"
    else
      echo "  WARNING: both FILE_INDEX.md and INDEX.md exist — review manually"
      # TODO
      # Same as safe_copy (offer to show diff, etc...)
    fi
  fi
  echo ""
  echo "  knowledge directory created"
  # tree "$TARGET/.claude/knowledge"
}


# ─────────────────────────────────────────────────────────────────────────────────
# ── Migrate from older versions ──

# _migration_prompt() { cat <<PROMPT # > "$1"
_migration_prompt() { cat <<PROMPT
You are updating knowledge entry frontmatter in ${1}/entries/
Do not read or edit files that are not mentioned in ${1}/incomplete-frontmatter.list
For each .md entry that IS on that list:
1. Read the file's YAML frontmatter (between the first pair of '---' delimiters at top of file)
2. If either of the following two fields are missing, add them with sensible values derived ONLY from the entry's existing content — do NOT explore the codebase:
   - category: infer from the entry's subdirectory name
   - tags: 2-4 keywords based on the entry's title and body text
3. If "inspected" is missing, just add the key, not a value:
   - inspected: do not add a value, only add the attribute if missing
4. Do NOT modify created, updated, or inspected timestamps that already exist
5. Do NOT change the entry body content
6. Do NOT read or edit any files not on the list or that are outside of ${1}/entries/
7. Use yq to update frontmatter in place:
   yq --front-matter=process '.tags = ["keyword1", "keyword2"]' -i <file>

Process every entry. When you are finished, just say "done".

PROMPT

}

_check_frontmatter() {
  [[ ! -f "$1/incomplete-frontmatter.list" ]] || rm "$1/incomplete-frontmatter.list"
  find "$1/entries" -name "*.md" -type f -exec grep -L -P "^(tags|category|inspected):" '{}' \; 2>/dev/null | tee "$1/incomplete-frontmatter.list" >/dev/null
}

_migration() {
  [[ -d "$1" ]] || return 0
  local KNOWLEDGE_DIR="$1"
  echo "Inspecting existing $KNOWLEDGE_DIR ..."

  _check_frontmatter "$KNOWLEDGE_DIR"
  if [[ -s "$KNOWLEDGE_DIR/incomplete-frontmatter.list" ]]; then
    printf '\n  %s\n\n' "$(wc -l < "$KNOWLEDGE_DIR/incomplete-frontmatter.list") entries missing new frontmatter fields (tags, category, inspected)."
    read -rep "Backfill missing fields (using claude -p)? [y/N]: " update_entries
    if [[ "${update_entries,,}" == y?(es) ]]; then
      printf '\n%s\n\n' "Summoning a claude to backfill missing frontmatter fields..."
      claude --allowedTools "Edit,Write,Bash(yq *),Bash(find *)" -p "$(_migration_prompt "$KNOWLEDGE_DIR")"
      echo ""
    fi
    printf '\n\n%s\n\n' "Checking claude's work..."
    _check_frontmatter "$KNOWLEDGE_DIR"
    if [[ -s "$KNOWLEDGE_DIR/incomplete-frontmatter.list" ]]; then
      printf '\n%b%s%b %s\n%b%s%b %s\n\n%s\n[\e[3m%s\e[0m](\e[0;38;2;69;138;255m%s\e[0m)\n\n' \
        '\e[1;3;38;2;180;69;240m' 'Anomylous activity' '\e[0m' \
        "detected in '$KNOWLEDGE_DIR/incomplete-frontmatter.list'" \
        '\e[1;3;37m' 'Remain calm.' '\e[0m' 'Avoid eye-lid blinking to the best of your ability.' \
        'Contact your nearest Knowledge Brigade Agency handler as soon as possible.' \
        'KBA Contact Form' 'https://github.com/asmrtfm/claude-knowledge/issues'
    else
      echo "Everything seems in order."
    fi
  fi
}


# ─────────────────────────────────────────────────────────────────────────────────
# Register a repo in the org's settings files.
# settings.json (portable): ORG_NAME, CLAUDE_SCOPE
# settings.local.json (local): ORG_DIR, additionalDirectories
# Args: <org_dir> <repo_root> <repo_name>
_register_repo_in_org() {
  local org_dir="$1" repo_root="$2" repo_name="$3"
  local org_settings="$org_dir/.claude/settings.json"
  local org_local="$org_dir/.claude/settings.local.json"
  local org_name="${ORG_NAME:-$(basename "$org_dir")}"
  mkdir -p "$org_dir/.claude"

  # settings.json: ORG_NAME + CLAUDE_SCOPE (versioned, shared)
  local org_env result
  org_env=$(jq -n --arg on "$org_name" '{ORG_NAME:$on, CLAUDE_SCOPE:"org"}') || {
    echo "[ERROR] failed to build org env JSON (org_name='$org_name')" >&2; return 1; }
  if [[ -s "$org_settings" ]]; then
    result=$(jq --argjson env "$org_env" '.env = ((.env // {}) + $env)' "$org_settings") || {
      echo "[ERROR] failed to merge env into $org_settings" >&2; return 1; }
    printf '%s\n' "$result" > "$org_settings"
  else
    jq -n --argjson env "$org_env" '{env:$env}' > "$org_settings"
  fi

  # settings.local.json: ORG_DIR + additionalDirectories (git-ignored, absolute paths)
  if [[ -s "$org_local" ]]; then
    result=$(jq \
      --arg od "$org_dir" \
      --arg dir "$repo_root" \
      '.env = ((.env // {}) + {ORG_DIR:$od}) | .permissions.additionalDirectories = (((.permissions // {}).additionalDirectories // []) | if index($dir) then . else . + [$dir] end)' \
      "$org_local") || {
      echo "[ERROR] failed to merge into $org_local" >&2; return 1; }
    printf '%s\n' "$result" > "$org_local"
  else
    jq -n --arg od "$org_dir" --arg dir "$repo_root" \
      '{env:{ORG_DIR:$od}, permissions:{additionalDirectories:[$dir]}}' > "$org_local"
  fi
  echo "  registered $repo_name in org settings"
}


# ─────────────────────────────────────────────────────────────────────────────────
# Merge helpers — add hooks+permissions to the chosen file, env to both
#
# Merge env, hooks, and permissions into a settings file without clobbering existing content.
_merge_hooks_and_env() {
  local settings_file="$1" env_block="$2"
  local was_readonly=false
  # Temporarily make writable if read-only
  if [[ -f "$settings_file" && ! -w "$settings_file" ]]; then
    was_readonly=true
    chmod +w "$settings_file"
  fi
  # Capture jq output in a variable first — never redirect jq directly to the
  # input file, because the shell truncates the file before jq reads it.
  local result
  if [[ "$settings_file" == "$SETTINGS" ]]; then
    if [[ -s "$settings_file" ]]; then
      result=$(jq \
        --argjson env "$env_block" \
        --argjson hooks "$(_settings_hooks)" \
        --argjson perms "$settings_permissions_allow" \
        '.env = ((.env // {}) + $env) | .hooks = (reduce ($hooks | to_entries[]) as $e (.hooks // {}; .[$e.key] = ((.[$e.key] // []) as $existing | $existing + [$e.value[] | select(.matcher as $m | [$existing[].matcher] | index($m) | not)]))) | .permissions.allow = (((.permissions // {}).allow // []) + ($perms - ((.permissions // {}).allow // [])))' "$settings_file")
      [[ -n "$result" ]] && printf '%s\n' "$result" > "$settings_file"
    else
      jq -n --argjson env "$env_block" --argjson hooks "$(_settings_hooks)" --argjson perms "$settings_permissions_allow" '{env:$env,hooks:$hooks,permissions:{allow:$perms}}' > "$settings_file"
    fi
  else
    if [[ -s "$settings_file" ]]; then
      result=$(jq --argjson env "$env_block" '.env = ((.env // {}) + $env)' "$settings_file")
      [[ -n "$result" ]] && printf '%s\n' "$result" > "$settings_file"
    else
      jq -n --argjson env "$env_block" '{env:$env}' > "$settings_file"
    fi
  fi
  if [[ "$was_readonly" == true ]]; then
    chmod -w "$settings_file"
  fi

  echo "UPDATED ${settings_file##*\/}"
}




# ─────────────────────────────────────────────────────────────────────────────────
# Oh my god I fucking hate this
# but since it WAS working and I've already speant all day rewriting Claude's slop,
# I'm leaving it for now...
# ---------------------------

# ── Determine install mode ──
if [[ -z $MODE ]]; then
  if [[ -n $ORG_DIR ]]; then
    MODE="org"
    export ORG_DIR="$TARGET"
  elif [[ -n $REPO_NAME || -d "$TARGET/.git" ]]; then
    MODE="repo"
    export REPO_ROOT="$TARGET"
  elif [[ -n $PROJECT_NAME ]]; then
    MODE="project"
    export PROJECT_ROOT="$TARGET"
  fi
fi

# ── Collect values ──
# Prompt for names, confirm paths. By the end of this block:
#   org:     ORG_NAME, ORG_DIR are set
#   project: PROJECT_NAME, PROJECT_ROOT are set
#   repo:    REPO_NAME, REPO_ROOT are set, optionally ORG_NAME + ORG_DIR

echo "[DEBUG]  MODE: $MODE"
# exit 0
case "$MODE" in
"org")
  # Org mode: dir is the target itself, just need the name
  ORG_NAME=$(prompt_value "ORG_NAME" "$(basename "${ORG_DIR:-$TARGET}")")
  ORG_DIR="${ORG_DIR:-$TARGET}"
  echo ""
  echo "  ORG_NAME: $ORG_NAME"
  echo "  ORG_DIR:  $ORG_DIR"
  ;;
*)
  if [[ -d "${REPO_ROOT:-${PROJECT_ROOT:-$TARGET}}/.git" ]]; then
    MODE=repo
    REPO_NAME=$(prompt_value "REPO_NAME" "${REPO_NAME:-$(basename "${REPO_ROOT:-$TARGET}")}")
    REPO_ROOT="${REPO_ROOT:-$TARGET}"

    # Probe for a parent org dir — _set_org_dir may fail on repos with no remote,
    # so fall back to the parent directory basename as a placeholder.
    _set_org_dir 2>/dev/null || true
    if [[ -z $ORG_DIR ]]; then
      ORG_DIR="$(dirname "${REPO_ROOT:-$TARGET}")"
      ORG_NAME="${ORG_DIR##*/}"
    fi
    read -rep "  Does this repo belong to an org that will use claude-knowledge? [y/N]: " use_org
    if [[ "${use_org,,}" == y?(es) ]]; then
      ORG_NAME=$(prompt_value "ORG_NAME" "$ORG_NAME")
    else
      ORG_DIR=""
      ORG_NAME=""
    fi
    echo ""
    echo "  REPO_NAME: $REPO_NAME"
    echo "  REPO_ROOT: $REPO_ROOT"
    [[ -z $ORG_DIR ]] || echo "  ORG_NAME:  $ORG_NAME"
    [[ -z $ORG_DIR ]] || echo "  ORG_DIR:   $ORG_DIR"
  else
    MODE=project
    PROJECT_NAME=$(prompt_value "PROJECT_NAME" "$(basename "${PROJECT_ROOT:-$TARGET}")")
    echo ""
    echo "  PROJECT_NAME: $PROJECT_NAME"
    echo "  PROJECT_ROOT: ${PROJECT_ROOT:=$TARGET}"
    ORG_DIR=""
    ORG_NAME=""
    REPO_NAME=""
    REPO_ROOT=""
  fi
esac

echo ""
read -rep "Look good? [Y/n]: " confirm
if [[ "${confirm,,}" != @(y)?(es) ]]; then
  echo "Aborted."
  exit 0
fi
echo ""


_ask_settings

# ─── Build env blocks for settings.json ───
# Portable env (settings.json): names + CLAUDE_SCOPE — no absolute paths
# Local env (settings.local.json): absolute paths — git-ignored
if [[ "$MODE" == "org" ]]; then
  env_json=$(jq -n --arg on "$ORG_NAME" '{ORG_NAME:$on, CLAUDE_SCOPE:"org"}')
  local_env_json=$(jq -n --arg od "$ORG_DIR" '{ORG_DIR:$od}')
elif [[ "$MODE" == "project" ]]; then
  env_json=$(jq -n --arg pn "$PROJECT_NAME" '{PROJECT_NAME:$pn, CLAUDE_SCOPE:"project"}')
  local_env_json=$(jq -n --arg pr "$PROJECT_ROOT" '{PROJECT_ROOT:$pr}')
else
  env_json=$(jq -n --arg rn "$REPO_NAME" '{REPO_NAME:$rn, CLAUDE_SCOPE:"repo"}')
  local_env_json=$(jq -n --arg rr "$REPO_ROOT" '{REPO_ROOT:$rr}')
  # Repo also gets org vars so hooks can find org-level knowledge
  if [[ -n $ORG_DIR ]]; then
    env_json=$(printf '%s' "$env_json" | jq --arg on "$ORG_NAME" '. + {ORG_NAME:$on}')
    local_env_json=$(printf '%s' "$local_env_json" | jq --arg od "$ORG_DIR" '. + {ORG_DIR:$od}')
  fi
fi



# ─────────────────────────────────────────────────────────────────────────────────
_install_hooks

_install_skill

# Run migration before creating dirs — _migration guards on [[ -d "$1" ]]
# so it correctly no-ops on fresh installs where the dir doesn't exist yet.
_inspect_org() { _migration "$ORG_DIR/.claude/knowledge"; }
_inspect_project() { _migration "${REPO_ROOT:-$PROJECT_ROOT}/.claude/knowledge"; }

if [[ -n $ORG_DIR ]]; then
  _inspect_org
  _inspect_project
elif [[ -n ${REPO_ROOT:-$PROJECT_ROOT} ]]; then
  _inspect_project
fi

_establish_knowledge_dir


# settings.json gets portable env (names only); hooks only if user chose settings.json
_merge_hooks_and_env "$TARGET/.claude/settings.json" "$env_json"

# settings.local.json gets local env (absolute paths); hooks only if user chose it
_merge_hooks_and_env "$TARGET/.claude/settings.local.json" "$local_env_json"

# Register this repo in the org's additionalDirectories so org-level Claude sessions can reach it
echo "[DEBUG] MODE=$MODE ORG_DIR=$ORG_DIR REPO_ROOT=$REPO_ROOT REPO_NAME=$REPO_NAME"
if [[ "$MODE" == "repo" && -n "$ORG_DIR" ]]; then
  _register_repo_in_org "$ORG_DIR" "$REPO_ROOT" "$REPO_NAME"
fi

_tell_configured_hooks


# ── Generate .envrc ──
# Writes the same env vars that go into settings, so shell tools (like `knowledge`) get them too.

#  if grep -vqs "Generated by knowledge init" "$ENVRC_FILE" >/dev/null; then
ENVRC_FILE="$TARGET/.envrc"
if [[ -f "$ENVRC_FILE" ]]; then
  ExistingEnvs="$(grep -vE "^(\#[^\!]|(export )?(ORG|REPO|PROJECT|KNOWLEDGE|CLAUDE))" "$ENVRC_FILE")"
  echo "$ExistingEnvs" > "$ENVRC_FILE"
else
  { echo '#!/usr/bin/env bash'; echo ""; } > "$ENVRC_FILE"
fi
{
  if [[ "$MODE" == "org" ]]; then
    echo "export ORG_NAME=\"$ORG_NAME\""
    echo "export ORG_DIR=\"$ORG_DIR\""
    echo "export CLAUDE_SCOPE=\"org\""
  elif [[ "$MODE" == "project" ]]; then
    echo "export PROJECT_NAME=\"$PROJECT_NAME\""
    echo "export PROJECT_ROOT=\"$PROJECT_ROOT\""
    echo "export CLAUDE_SCOPE=\"project\""
  else
    echo "export REPO_NAME=\"$REPO_NAME\""
    echo "export REPO_ROOT=\"$REPO_ROOT\""
    echo "export CLAUDE_SCOPE=\"repo\""
    if [[ -n $ORG_DIR ]]; then
      echo "export ORG_NAME=\"$ORG_NAME\""
      echo "export ORG_DIR=\"$ORG_DIR\""
    fi
  fi
} >> "$ENVRC_FILE"

chmod +x "$ENVRC_FILE"
echo "Generated $ENVRC_FILE"


# Post-install verification
source "$(dirname "$SELF")/verify-settings.sh"
echo ""
echo "Done. Run '/knowledge capture' in a Claude session to start building entries."
