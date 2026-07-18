#!/usr/bin/env bash

# TESTS
#
# cd ~/Workspaces/night-district/night-district-core
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "grep -RIns \"Stickers\"" } }' | .claude/hooks/knowledge/pre-search.sh
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "find -type f -iwholename \"*config/routes/hq.rb\"" } }' | .claude/hooks/knowledge/pre-search.sh


if [[ -s "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi


# EVENT: PreToolUse
# Intercepts Bash search commands (find/grep/rg) to surface relevant knowledge entries alongside normal search results.
#
# How it works:
#   1. Run the Clanker's command, capture the output, parse any file paths.
#   2. If the paths are absolute, strip them to be relative to ${REPO_ROOT:-$PROJECT_ROOT}
#   3. For each resulting relative file path, look it up in .claude/knowledge/INDEX.md and collect any linked knowledge entries.
#   4. Do the same for the org knowledge if the repo is registered with an org.
#   5. Surface the matched knowledge entries via `"additionalContext": { "knowledge":[<entries ...>], "org_knowledge":[<org_entries ...>] }`


Input="$(cat)"

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
  *'find '*) Cmd="find" ;;
  *'grep '*) _is_recursive "$cmd" || exit 0 ;;
  *'rg '*) ;;
  *) exit 0 ;;
esac


. "${BASH_SOURCE[0]%\/*}/lib/resolve-env.sh"
_set_repo_root
_set_org_dir


# Step 0: create an output file in which to capture the output of their command. use the toolcall_id as the basename.
tool_use_id=$(printf '%s' "$Input" | jq -r '.tool_use_id // ""')
# echo "tool_use_id: ${tool_use_id}"

to="$(mktemp -d)/${tool_use_id}"
# echo "to: ${to}"

# Step 1: Run their command, capture file list
if [[ $Cmd == "find" ]]; then
  declare -i fc=$(bp '??e' < <({ { eval ${cmd} || true; } 2>/dev/null; } | tee "${to}.log") | tee "${to}.list" | wc -l)
else
  declare -i fc=$(bp '%%\:*' < <({ { eval ${cmd} || true; } 2>/dev/null; } | tee "${to}.log") | tee "${to}.list" | wc -l)
fi

# TODO
# depending on the current strategy shakes out, we may want to handle cleanup.
# Perhaps move resultts into /tmp/claude-code/tool-results/...
#
# _cleanup() {
#   if [[ -n $HOOKS_DEBUG ]]; then
#     echo "[DEBUG] output preserved in: ${to%\/*}"
#   else
#     rm -rf "${to%\/*}"
#   fi
#   exit 0
# }
#
# ((fc > 0)) || _cleanup
#
# trap _cleanup EXIT SIGTERM SIGKILL SIGHUP


_parse_entries() { grep -Po "$1 -> \[\K.*(?=\])" "$2" | sed 's|[\,]\s*|\n|g;s|[\"]||g'; }


declare -a files=()

while IFS= read -r line ; do
  [[ "$line" != "./" ]] || line="${line:2}"
  if [[ ! -f "$line" ]]; then
    [[ -f "${line%%[[:space:]]*}" ]] || continue
    [[ "${files[*]}" == *"${line%%[[:space:]]*}"* ]] || files[${#files[@]}]="${line%%[[:space:]]*}"
  else
    [[ "${files[*]}" == *"$line"* ]] || files[${#files[@]}]="$line"
  fi
done < <([[ "$Cmd" != "find" ]] && cat "${to}.list" || { cat "${to}.list" | xargs realpath; } )


# if EnvRC=$(nearest --from "${REPO_ROOT:-${PROJECT_ROOT:-$(pwd)}}" -x ".envrc"); then
#   . "$EnvRC"
# fi
if EnvRC=$(nearest -x .envrc); then
  . "$EnvRC"
fi

if KnowledgeBase="$(nearest --from "${REPO_ROOT:-${PROJECT_ROOT:-$(pwd)}}" -d {.claude,docs}/knowledge)"; then
  [[ -f "${KnowledgeBase}/INDEX.md" ]] || unset KnowledgeBase
fi

if [[ -d "$REPO_ROOT" && -d "$ORG_DIR" && "$CLAUDE_SCOPE" != "project" ]]; then
  # Handles edge case of using different name than basename of directory in their config
  REPO_NAME="${REPO_ROOT#*$ORG_DIR}"
  # Find the org knowledge directory if it exists
  if OrgKnowledge="$(nearest --from "${ORG_DIR:-${REPO_ROOT%\/*}}" -d {.claude,docs}/knowledge)"; then
    [[ -f "${OrgKnowledge}/INDEX.md" ]] || unset OrgKnowledge
  fi
fi

# Process for repo|project knowledge
if [[ -d "$KnowledgeBase" ]]; then
  for ((f=0;f<${#files[@]};f++)); do
    while read line ; do
      [[ ! -e "${KnowledgeBase}/entries/${line}" || "${entries[*]}" == *"$line"* ]] || entries[${#entries[@]}]="$line"
    done < <(_parse_entries "${files[f]#*${REPO_ROOT:-${PROJECT_ROOT:-${REPO_NAME:-$PROJECT_NAME}}}\/}" "${KnowledgeBase}/INDEX.md" 2>/dev/null)
  done
fi


# Process for org knowledge
if [[ -d "$OrgKnowledge" ]]; then
  for ((f=0;f<${#files[@]};f++)); do
    while read line ; do
      [[ ! -e "${OrgKnowledge}/entries/${line}" || "${org_entries[*]}" == *"$line"* ]] || org_entries[${#org_entries[@]}]="$line"
    done < <(_parse_entries "${files[f]#*${ORG_DIR}\/}" "${OrgKnowledge}/INDEX.md" 2>/dev/null)
  done
fi


# Output: surface matched knowledge entries via additionalContext
ctx_json="{}"

for ((i=0;i<${#entries[@]};i++)); do
  ctx_json=$(printf '%s' "$ctx_json" | jq --arg e "${KnowledgeBase}/entries/${entries[i]}" '.knowledge += [$e]')
done

for ((i=0;i<${#org_entries[@]};i++)); do
  ctx_json=$(printf '%s' "$ctx_json" | jq --arg e "${OrgKnowledge}/entries/${org_entries[i]}" '.org_knowledge += [$e]')
done

if [[ "$ctx_json" != "{}" ]]; then
  if ((fc > 99)); then
    new_cmd="echo \"[COMMAND]: $cmd\"; echo \"\"; echo \"[RESULTS](large output captured in): ${to}.log\"; wc -l \"${to}.log\""
  else
    new_cmd="echo \"[COMMAND]:\"; echo \"$cmd\"; echo \"\"; echo \"[RESULTS]:\"; cat \"${to}.log\""
  fi
  printf '%s' "$Input" | jq \
    --argjson ctx "$ctx_json" \
    --arg nc "$new_cmd" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: $ctx,
      updatedInput: (.tool_input | .command = $nc)
    }
  }'
else
  printf '%s' "$Input" | jq '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      additionalContext: "Tool call resulted in empty output"
    }
  }'
fi
