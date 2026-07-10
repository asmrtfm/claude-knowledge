#!/usr/bin/env bash

if [[ -f "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi


# EVENT: PreToolUse
# Intercepts Bash search commands (find/grep/rg) to surface relevant knowledge
# entries alongside normal search results.
#
# How it works:
#   1. Run the user's command to get a file list. For grep/rg without -l, we add
#      -l to our copy so we get paths instead of content lines.
#   2. For each file path in the output, look it up in INDEX.md via exact prefix
#      match ("^<filepath> -> "). If the file is indexed, its knowledge entry
#      mapping is collected.
#   3. If the user's command produced NO results (no files matched in the
#      codebase), re-run their exact command but with the search target path
#      swapped to each knowledge base's entries/ subdirectory. This searches
#      knowledge content directly using their original pattern and flags.
#
# The original command always runs unmodified. Knowledge results, if any, are
# prepended as a separate "=== KNOWLEDGE ENTRIES ===" block.

Input="$(cat)"

# ---
# Not necessary, the settings.json already has a Bash matcher
#
# tool_name=$(printf '%s' "$Input" | jq -r '.tool_name // ""')
# [[ "$tool_name" == "Bash" ]] || exit 0
# ---

cmd=$(printf '%s' "$Input" | jq -r '.tool_input.command // ""')


# Only gate commands that invoke grep (any variant: grep, egrep, fgrep, ugrep, rgrep)
#                             ( intentionally avoids matching on  ast-grep )
_is_recursive() {
  [[ "$@" == ?([a-z])@('grep'|'rg'|'ripgrep')+([[:space:]])+(\-)*([[:alnum:]])@([rR])* || \
     "$@" == *\|+(\ )?([a-z])@('grep'|'rg'|'ripgrep')+([[:space:]])+(\-)*([[:alnum:]])@([rR])* || \
     "$@" == @('rg'|'ripgrep')* \
  ]]
}


# Only intercept search commands
case "$cmd" in
  *'ast-grep'*) exit 0 ;;
  *'find '*) ;;
  *'grep '*) _is_recursive "$cmd" || exit 0 ;;
  *'rg '*) ;;
  *) exit 0 ;;
esac

# Extract search terms from the command
declare -ga terms=()

find_flag_values() {
  local flag="$1"
  local text="$2"
  # Match -flag <value> pairs, stripping quotes and globs
  while [[ "$text" =~ -${flag}[[:space:]]+([^[:space:]]+) ]]; do
    local val="${BASH_REMATCH[1]}"
    val="${val//\"/}"
    val="${val//\'/}"
    val="${val//\*/}"
    [[ -n "$val" ]] && terms+=("$val")
    text="${text#*"${BASH_REMATCH[0]}"}"
  done
}

case "$cmd" in
  *'find '*)
    for flag in name iname wholename iwholename path ipath; do
      find_flag_values "$flag" "$cmd"
    done
    ;;
  *'grep '*|*'rg '*)
    # Extract the pattern: first positional arg after flags
    # Strip the command prefix up to grep/rg
    local_cmd="${cmd##*grep }"
    [[ "$cmd" == *'rg '* ]] && local_cmd="${cmd##*rg }"
    for part in $local_cmd; do
      # Skip flags and their arguments
      [[ "$part" == -* ]] && continue
      # Skip common path arguments
      [[ -e "$part" || "$part" == "." || "$part" == "./" ]] && continue
      # First non-flag, non-path token is likely the pattern
      part="${part//\"/}"
      part="${part//\'/}"
      [[ -n "$part" ]] && terms+=("$part")
      break
    done
    ;;
esac

# query="${terms[*]}"
# [[ -n "$query" ]] || query="(could not extract search terms)"
# 
# printf '%s' "$Input" | jq \
#   --arg reason "Search intercepted — check /knowledge before blind searches." \
#   --arg context "IMPORTANT: Before retrying this search, check the /knowledge system for existing notes. Run: /knowledge $query" \
#   '{
#     hookSpecificOutput: {
#       hookEventName: "PreToolUse",
#       permissionDecision: "ask",
#       permissionDecisionReason: $reason,
#       additionalContext: $context
#     }
#   }'

# for ((i=0;i<${#terms[@]};i++)); do
#   query="${terms[i]}|"
# done
# [[ -n "$query" ]] || exit 0
# query="(${query:: -1})"
# if [[ "$query" == '(('*'))' && "${query:2:${#query}-4}" != *\)*\(* ]]; then
#   query="${query:1: -1}"
# fi

# printf '%s' "$Input" | jq \
#   --arg reason "Search intercepted — check /knowledge before blind searches." \
#   --arg context "IMPORTANT: Before retrying this search, check the /knowledge system for existing notes. Run: grep -liIRs $query" \
#   '{
#     hookSpecificOutput: {
#       hookEventName: "PreToolUse",
#       permissionDecision: "ask",
#       permissionDecisionReason: $reason,
#       additionalContext: $context
#     }
#   }'

. "${BASH_SOURCE[0]%/*}/lib/resolve-env.sh"
_set_repo_root
_set_org_dir

# --- original inline knowledge dir resolution ---
# declare -a KNOWLEDGE_BASE=()
# [[ ! -d "${ORG_DIR}/.claude/knowledge" ]] || KNOWLEDGE_BASE[0]="${ORG_DIR}/.claude/knowledge"
# [[ ! -d "${REPO_ROOT}/.claude/knowledge" ]] || KNOWLEDGE_BASE[1]="${REPO_ROOT}/.claude/knowledge"

mapfile -t KNOWLEDGE_BASE < <(_resolve_knowledge_dirs)
[[ ${#KNOWLEDGE_BASE[@]} -gt 0 ]] || exit 0

# Build a file-list variant of their command:
#   grep/rg without -l gets -l added; find outputs paths already
_make_filelist_cmd() {
  local c="$1"
  case "$c" in
    *'find '*)
      printf '%s' "$c"
      ;;
    *'grep '*|*'rg '*)
      if [[ "$c" =~ (^|[[:space:]])-[a-zA-Z]*l|--files-with-matches ]]; then
        printf '%s' "$c"
      elif [[ "$c" == *'rg '* ]]; then
        printf '%s' "${c/rg /rg -l }"
      else
        printf '%s' "${c/grep /grep -l }"
      fi
      ;;
  esac
}

# Build a fallback command: their exact command with the search target
# swapped to each knowledge entries directory.
_make_kb_fallback_cmd() {
  local c="$1"
  shift
  local kb_dirs=("$@")

  # Find the target path — last argument that looks like a path
  local target=""
  local last_was_flag=false
  for part in $c; do
    case "$part" in
      -*) last_was_flag=true; continue ;;
    esac
    if $last_was_flag; then
      last_was_flag=false
      continue
    fi
    if [[ "$part" == */* || "$part" == "." || -e "$part" ]]; then
      target="$part"
    fi
  done
  [[ -n "$target" ]] || return 1

  local parts=()
  for kb_dir in "${kb_dirs[@]}"; do
    local entries_dir="$kb_dir/entries"
    [[ -d "$entries_dir" ]] || continue
    local modified="${c%"$target"*}${entries_dir}${c##*"$target"}"
    parts+=("$modified")
  done
  [[ ${#parts[@]} -gt 0 ]] || return 1
  local IFS='; '
  printf '%s' "${parts[*]}"
}

# Step 1: Run their command, capture file list
filelist_cmd=$(_make_filelist_cmd "$cmd")
filelist_output=$(eval "$filelist_cmd" 2>/dev/null)

# Step 2: Look up each result path in INDEX.md
kb_results=""
if [[ -n "$filelist_output" ]]; then
  while IFS= read -r filepath; do
    [[ -n "$filepath" ]] || continue
    filepath="${filepath#./}"
    for kb_dir in "${KNOWLEDGE_BASE[@]}"; do
      [[ -f "$kb_dir/INDEX.md" ]] || continue
      match=$(grep "^${filepath} -> " "$kb_dir/INDEX.md" 2>/dev/null)
      if [[ -z "$match" && -n "$REPO_ROOT" ]]; then
        local_path="${filepath#"$REPO_ROOT"/}"
        match=$(grep "^${local_path} -> " "$kb_dir/INDEX.md" 2>/dev/null)
      fi
      [[ -n "$match" ]] && kb_results+="$match"$'\n'
    done
  done <<< "$filelist_output"
fi

# Step 3: If their command produced no results, run their exact command
# against knowledge entries directories instead
kb_fallback=""
if [[ -z "$filelist_output" ]]; then
  fallback_cmd=$(_make_kb_fallback_cmd "$cmd" "${KNOWLEDGE_BASE[@]}")
  if [[ -n "$fallback_cmd" ]]; then
    kb_fallback=$(eval "$fallback_cmd" 2>/dev/null)
  fi
fi

# Output: pass knowledge entries via additionalContext, let the command through unchanged
if [[ -n "$kb_results" || -n "$kb_fallback" ]]; then
  kb_combined=""
  [[ -n "$kb_results" ]] && kb_combined+="$kb_results"
  [[ -n "$kb_fallback" ]] && kb_combined+="$kb_fallback"
  printf '%s' "$Input" | jq \
    --arg ctx "$kb_combined" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: ("Matching knowledge entries:\n" + $ctx)
      }
    }'
else
  printf '%s' "$Input" | jq \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow"
      }
    }'
fi

# --- previous approach: prepend echo to command output ---
# if [[ -n "$kb_results" || -n "$kb_fallback" ]]; then
#   kb_combined=""
#   [[ -n "$kb_results" ]] && kb_combined+="$kb_results"
#   [[ -n "$kb_fallback" ]] && kb_combined+="$kb_fallback"
#   kb_escaped=$(printf '%s' "$kb_combined" | jq -Rs .)
#   printf '%s' "$Input" | jq \
#     --arg new_cmd "echo \"=== KNOWLEDGE ENTRIES ===\"; echo ${kb_escaped}; echo \"---\"; ${cmd}" \
#     '{
#       hookSpecificOutput: {
#         hookEventName: "PreToolUse",
#         permissionDecision: "allow",
#         updatedInput: (.tool_input | .command = $new_cmd)
#       }
#     }'
# else
#   printf '%s' "$Input" | jq \
#     '{
#       hookSpecificOutput: {
#         hookEventName: "PreToolUse",
#         permissionDecision: "allow"
#       }
#     }'
# fi

# # Fallback: content search via query-knowledge.sh if INDEX had no hits
# if [[ -z "$kb_results" ]]; then
#   QUERY_SCRIPT="${BASH_SOURCE[0]%/*}/lib/query-knowledge.sh"
#   for kb_dir in "${KNOWLEDGE_BASE[@]}"; do
#     kb_results+="$(bash "$QUERY_SCRIPT" "$kb_dir" "${terms[*]}")"
#   done
# fi

# --- original inline grep approach ---
# printf '%s' "$Input" | jq \
#   --arg new_cmd "echo \"=== KNOWLEDGE ENTRIES ===\"; grep -liIRs \"$query\" ${KNOWLEDGE_BASE[*]}; echo \"---\"; ${cmd}" \
#   '{
#     hookSpecificOutput: {
#       hookEventName: "PreToolUse",
#       permissionDecision: "allow",
#       updatedInput: (.tool_input | .command = $new_cmd)
#     }
#   }'
