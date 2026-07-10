#!/usr/bin/env bash
# Installs the knowledge hook system into a target project or org workspace.
# Usage: install.sh [--repo | --org | --update] [target_dir]
#        Defaults to current directory if no target given.

SELF="$(realpath "${BASH_SOURCE[0]}")"
SOURCE_DIR="${SELF%\/*}"

# ── Parse flags ──

MODE=""
UPDATE_ONLY=false
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --repo)   MODE="repo" ;;
    --org)    MODE="org" ;;
    --update) UPDATE_ONLY=true ;;
    *)        TARGET="$arg" ;;
  esac
done
TARGET="$(realpath "${TARGET:-.}")"

[[ -d "$TARGET" ]] || { echo "Target directory does not exist: $TARGET"; exit 1; }

# Copy src to dest, prompting if dest exists and differs
safe_copy() {
  local src="$1" dest="$2"
  if [[ -f "$dest" ]] && ! diff -q "$src" "$dest" &>/dev/null; then
    echo ""
    diff -u "$dest" "$src" | head -40
    echo ""
    read -rp "  Overwrite $(basename "$dest")? [y/N]: " answer
    [[ "$answer" == [yY]* ]] || return 0
  fi
  cp "$src" "$dest"
}

# Prompt for a value with a default placeholder
prompt_value() {
  local label="$1" default="$2" result
  read -rp "  ${label} [${default}]: " result
  echo "${result:-$default}"
}

if [[ "$UPDATE_ONLY" == true ]]; then
  echo ""
  echo "Updating knowledge system in: $TARGET"
  echo ""
  KNOWLEDGE_DIR="$TARGET/.claude/knowledge"
  [[ -d "$KNOWLEDGE_DIR" ]] || { echo "No knowledge directory found at $KNOWLEDGE_DIR"; exit 1; }
else

echo ""
echo "Installing knowledge system into: $TARGET"
echo ""

# ── Determine install mode ──

. "$SOURCE_DIR/.claude/hooks/knowledge/lib/resolve-env.sh"

if [[ "$MODE" == "org" ]]; then
  # Explicit --org flag
  :
elif [[ "$MODE" == "repo" ]]; then
  # Explicit --repo flag — resolve from filesystem
  _set_repo_root "$TARGET"
  _set_org_dir
elif [[ -d "$TARGET/.git" ]]; then
  # Target is a git repo
  MODE="repo"
  _set_repo_root "$TARGET"
  _set_org_dir
else
  # Not a git repo — ask if this is an org workspace
  echo "  '$TARGET' is not a git repository."
  read -rp "  Is this an org workspace? [Y/n]: " is_org
  if [[ "$is_org" != [nN]* ]]; then
    MODE="org"
  else
    MODE="repo"
  fi
fi

# ── Collect values ──

if [[ "$MODE" == "org" ]]; then
  ORG_NAME=$(prompt_value "ORG_NAME" "$(basename "$TARGET")")
  ORG_DIR="$TARGET"

  echo ""
  echo "  ORG_NAME: $ORG_NAME"
  echo "  ORG_DIR:  $ORG_DIR"
else
  REPO_NAME=$(prompt_value "REPO_NAME" "${REPO_NAME:-$(basename "$TARGET")}")
  REPO_ROOT="${REPO_ROOT:-$TARGET}"

  if [[ -n $ORG_DIR ]]; then
    read -rp "  Install as part of org '$ORG_NAME'? [y/N]: " use_org
    if [[ "$use_org" == [yY]* ]]; then
      ORG_NAME=$(prompt_value "ORG_NAME" "$ORG_NAME")
    else
      ORG_DIR=""
      ORG_NAME=""
    fi
  fi

  echo ""
  echo "  REPO_NAME: $REPO_NAME"
  echo "  REPO_ROOT: $REPO_ROOT"
  [[ -z $ORG_DIR ]] || echo "  ORG_NAME:  $ORG_NAME"
  [[ -z $ORG_DIR ]] || echo "  ORG_DIR:   $ORG_DIR"
fi

echo ""
read -rp "Look good? [Y/n]: " confirm
[[ "$confirm" != [nN]* ]] || { echo "Aborted."; exit 0; }

echo ""

# ── Copy hooks ──

mkdir -p "$TARGET/.claude/hooks/knowledge/lib"
for hook in knowledge.sh pre-edit.sh maintenance-queue.sh; do
  safe_copy "$SOURCE_DIR/.claude/hooks/knowledge/$hook" "$TARGET/.claude/hooks/knowledge/$hook"
  chmod +x "$TARGET/.claude/hooks/knowledge/$hook"
done
for lib in resolve-env.sh query-knowledge.sh; do
  safe_copy "$SOURCE_DIR/.claude/hooks/knowledge/lib/$lib" "$TARGET/.claude/hooks/knowledge/lib/$lib"
done

echo "  hooks installed"

# ── Copy skill ──

mkdir -p "$TARGET/.claude/skills/knowledge/skills"
safe_copy "$SOURCE_DIR/.claude/skills/knowledge/SKILL.md" "$TARGET/.claude/skills/knowledge/SKILL.md"
safe_copy "$SOURCE_DIR/.claude/skills/knowledge/load-env.sh" "$TARGET/.claude/skills/knowledge/load-env.sh"
safe_copy "$SOURCE_DIR/.claude/skills/knowledge/maintenance-log.sh" "$TARGET/.claude/skills/knowledge/maintenance-log.sh"
chmod +x "$TARGET/.claude/skills/knowledge/load-env.sh"
chmod +x "$TARGET/.claude/skills/knowledge/maintenance-log.sh"

for sub in capture maintain query inspect; do
  if [[ -d "$SOURCE_DIR/.claude/skills/knowledge/skills/$sub" ]]; then
    mkdir -p "$TARGET/.claude/skills/knowledge/skills/$sub"
    safe_copy "$SOURCE_DIR/.claude/skills/knowledge/skills/$sub/SKILL.md" \
              "$TARGET/.claude/skills/knowledge/skills/$sub/SKILL.md"
  fi
done

echo "  skill installed"

# ── Create knowledge directory structure ──

mkdir -p "$TARGET/.claude/knowledge/entries"/{architecture,decisions,gotchas,relationships,workflows,domain}
mkdir -p "$TARGET/.claude/knowledge/historical"
mkdir -p "$TARGET/.claude/knowledge/inspections"
mkdir -p "$TARGET/.claude/knowledge/maintenance"

if [[ -f "$TARGET/.claude/knowledge/FILE_INDEX.md" && ! -f "$TARGET/.claude/knowledge/INDEX.md" ]]; then
  mv -v "$TARGET/.claude/knowledge/FILE_INDEX.md" "$TARGET/.claude/knowledge/INDEX.md"
elif [[ -f "$TARGET/.claude/knowledge/FILE_INDEX.md" && -f "$TARGET/.claude/knowledge/INDEX.md" ]]; then
  echo "  WARNING: both FILE_INDEX.md and INDEX.md exist — review manually"
fi

[[ -f "$TARGET/.claude/knowledge/INDEX.md" ]] || cat > "$TARGET/.claude/knowledge/INDEX.md" << 'EOF'
# Knowledge Map
# Maps source files to the knowledge entries that are relevant to them.
# Grep the left side for file paths, grep the right side for concepts/categories.
#
# Format: relative/path/to/source_file -> [category/entry-name.md, ...]

EOF

[[ -f "$TARGET/.claude/knowledge/MAINTENANCE_QUEUE" ]] || touch "$TARGET/.claude/knowledge/MAINTENANCE_QUEUE"

echo "  knowledge directory created"

fi # end UPDATE_ONLY skip

# ── Migrate from older versions ──

KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-$TARGET/.claude/knowledge}"

# Offer to backfill missing frontmatter — only if entries actually lack fields
_incomplete=$(find "$KNOWLEDGE_DIR/entries" -name '*.md' -type f -exec \
  grep -L -P '^(tags|category|files|inspected):' {} + 2>/dev/null | wc -l)
if [[ "$_incomplete" -gt 0 ]]; then
  echo ""
  echo "  $_incomplete entries missing frontmatter fields."
  read -rp "  Backfill missing fields (tags, category, etc)? [y/N]: " update_entries
  if [[ "$update_entries" == [yY]* ]]; then
    echo "  Launching claude to backfill frontmatter..."
    # Workaround: shell-snapshot bug dumps exported functions into $() subshells,
    # so passing the prompt via temp file + stdin instead of command substitution.
    _prompt_file=$(mktemp)
    cat > "$_prompt_file" <<PROMPT
You are updating knowledge entry frontmatter in $KNOWLEDGE_DIR/entries/.

For each .md file under that directory:
1. Read the file's YAML frontmatter (between the --- delimiters)
2. If any of these fields are missing, add them with sensible values derived
   ONLY from the entry's existing content — do NOT explore the codebase:
   - category: infer from the entry's subdirectory name
   - tags: 2-4 keywords based on the entry's title and body text
   - files: leave empty ([]) if not already present — do not guess file paths
   - inspected: leave empty if not already present
3. Do NOT modify created, updated, or inspected timestamps that already exist
4. Do NOT change the entry body content
5. Do NOT read or explore any files outside of $KNOWLEDGE_DIR/entries/
6. Use yq to update frontmatter in place:
   yq --front-matter=process '.tags = ["keyword1", "keyword2"]' -i <file>

Process every entry, then report a one-line summary of how many were updated.
PROMPT
    claude -p --allowedTools "Edit,Write,Bash(yq *),Bash(find *)" < "$_prompt_file"
    rm -f "$_prompt_file"
    echo "  frontmatter update complete"
  fi
fi

if [[ "$UPDATE_ONLY" != true ]]; then

# ── Wire up settings.json (portable) and settings.local.json (local paths) ──

SETTINGS="$TARGET/.claude/settings.json"
SETTINGS_LOCAL="$TARGET/.claude/settings.local.json"

# Build portable and local env blocks based on mode
if [[ "$MODE" == "org" ]]; then
  env_json=$(jq -n --arg on "$ORG_NAME" '{ORG_NAME:$on}')
  local_env_json=$(jq -n --arg od "$ORG_DIR" '{ORG_DIR:$od}')
else
  env_json=$(jq -n --arg rn "$REPO_NAME" '{REPO_NAME:$rn}')
  local_env_json=$(jq -n --arg rr "$REPO_ROOT" '{REPO_ROOT:$rr}')
  if [[ -n $ORG_DIR ]]; then
    env_json=$(printf '%s' "$env_json" | jq --arg on "$ORG_NAME" '. + {ORG_NAME:$on}')
    local_env_json=$(printf '%s' "$local_env_json" | jq --arg od "$ORG_DIR" '. + {ORG_DIR:$od}')
  fi
fi

# Build the hooks block
hooks_json=$(cat << 'HOOKS'
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": ".claude/hooks/knowledge/knowledge.sh", "shell": "bash"}]
    },
    {
      "matcher": "Edit|Write|NotebookEdit",
      "hooks": [{"type": "command", "command": ".claude/hooks/knowledge/pre-edit.sh", "shell": "bash"}]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Edit|Write|NotebookEdit",
      "hooks": [{"type": "command", "command": ".claude/hooks/knowledge/maintenance-queue.sh", "shell": "bash"}]
    }
  ]
}
HOOKS
)

# settings.json — portable env + hooks
if [[ -f "$SETTINGS" ]]; then
  existing=$(cat "$SETTINGS")
  printf '%s' "$existing" | jq \
    --argjson env "$env_json" \
    --argjson hooks "$hooks_json" \
    '.env = ((.env // {}) + $env) | .hooks = (reduce ($hooks | to_entries[]) as $e (.hooks // {}; .[$e.key] = ((.[$e.key] // []) + $e.value)))' \
    > "$SETTINGS"
  echo "  settings.json updated (merged)"
else
  jq -n --argjson env "$env_json" --argjson hooks "$hooks_json" \
    '{env:$env,hooks:$hooks}' > "$SETTINGS"
  echo "  settings.json created"
fi

# settings.local.json — local paths only
if [[ -f "$SETTINGS_LOCAL" ]]; then
  existing=$(cat "$SETTINGS_LOCAL")
  printf '%s' "$existing" | jq \
    --argjson env "$local_env_json" \
    '.env = ((.env // {}) + $env)' \
    > "$SETTINGS_LOCAL"
  echo "  settings.local.json updated (merged)"
else
  jq -n --argjson env "$local_env_json" \
    '{env:$env}' > "$SETTINGS_LOCAL"
  echo "  settings.local.json created"
fi

echo ""
echo "Done. Run '/knowledge capture' in a Claude session to start building entries."

fi # end UPDATE_ONLY skip for settings
