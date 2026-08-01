#!/usr/bin/env bash

# ---------------------------------------------------------------------------------
# If .claude/hooks/.disabled_hooks is a non-empty file, then bail early if we're in it.
#
if [[ -s "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" ]]; then
  grep -qEv "\b(knowledge|$(basename "${BASH_SOURCE[0]}" .sh))\b" "${BASH_SOURCE[0]%\/*}/../.disabled_hooks" || exit 0
fi
# This allows enabling/disabling them mid-session without having to jocky json in-and-out of .claude/settings.json
#
# - disable this hook by adding its basename to the list.
# - disable all knowledge-related hooks by adding 'knowledge' to the list.
# ---------------------------------------------------------------------------------



# ROADMAP:  Template engine that breaks out the useful points so we don't have to think about the boilerplate.
#           We handle deconstructing/disambiguating the tool_call.command into a more complete structure:
#                                                                 command: {
#                                                                        name: "",
#                                                                     options: [],
#                                                                      params: [],
#                                                                       stdin: []
#                                                                 }
#
#           When claude searches for <___>
#
#           AVAILABLE ACTION NODES (sequencable) - almost a minimal n8n
#           (): replace command with: <___>
#           (): 
# ---------

knerr() {
  if [[ "$1" != [0-9] ]]; then
    local this_hook="${BASH_SOURCE[0]##*\/hooks\/}"
    this_hook="${this_hook//'/'/'::'}"
    errMsg="[$(date)](${this_hook}): $*"
    echo "$errMsg" >> ~/.claude/hooks/errors.log
  else
    errMsg="${@:2}"
  fi
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical -c claude_hook "$errMsg"
  fi
}


# EVENT: PreToolUse
# Intercepts Bash search commands (find/grep/rg) to surface relevant knowledge entries alongside normal search results.
#
# How it works:
#   1. Run the Clanker's command, capture the output, parse any file paths.
#   2. If the paths are absolute, strip them to be relative to ${REPO_ROOT:-$PROJECT_ROOT}
#   3. For each resulting relative file path, look it up in .claude/knowledge/INDEX.md and collect any linked knowledge entries.
#   4. Do the same for the org knowledge if the repo is registered with an org.
#   5. Surface the matched knowledge entries via `"additionalContext": { "knowledge":[<entries ...>], "org_knowledge":[<org_entries ...>] }`

if [[ "${1,,}" == +(\-)'test' ]]; then
  if [[ ! -t 0 ]]; then
    cmd="$(cat)"
  else
    cmd="${@:2}"
  fi
  Input=$(jq -n --arg c "$cmd" '{ "tool_use_id": "toolu_123", "tool_input": { "command": $c } }')
else
  Input="$(cat)"
  cmd=$(printf '%s' "$Input" | jq -r '.tool_input.command // ""')
fi


# Only gate commands that invoke grep (any variant: grep, egrep, fgrep, ugrep, rgrep)
#                             ( intentionally avoids matching on  ast-grep )
_is_recursive() {
  [[ "$*" == ?([a-z])@('grep'|'rg'|'ripgrep')+([[:space:]])+(\-)*([[:alnum:]])@([rR])* || \
     "$*" == *\|+(\ )?([a-z])@('grep'|'rg'|'ripgrep')+([[:space:]])+(\-)*([[:alnum:]])@([rR])* || \
     "$*" == @('rg'|'ripgrep')* \
  ]]
}

# Only intercept search commands
case "$cmd" in
  *'ast-grep'*) exit 0 ;;
  *'find '*) Cmd="find" ;;
  *'grep '*) _is_recursive "$cmd" || exit 0; Cmd="grep" ;;
  *'rg '*) ;;
  *) exit 0 ;;
esac


. "${BASH_SOURCE[0]%\/*}/lib/resolve-env.sh"
_set_repo_root
_set_org_dir


# Step 0: create an output file in which to capture the output of their command. use the toolcall_id as the basename.
tool_use_id=$(printf '%s' "$Input" | jq -r '.tool_use_id // ""')
# echo "tool_use_id: ${tool_use_id}"

if [[ ! -d "$CLAUDE_LOCAL_CACHE" ]]; then
  CLAUDE_LOCAL_CACHE="${CLAUDE_LOCAL_CACHE:-$(nearest -d .claude)/cache}"
  mkdir -p "$CLAUDE_LOCAL_CACHE"
fi
to="${CLAUDE_LOCAL_CACHE}/${tool_use_id}"
# echo "to: ${to}"

# Step 1: Run their command, capture file list
# if [[ $Cmd == "find" ]]; then
#   declare -i fc=$(bp '??e' < <({ { eval "$cmd" || true; } 2>/dev/null; } | tee "${to}.log") | tee "${to}.list" | wc -l)
# else
#   declare -i fc=$(bp '%%\:*' < <({ { eval "$cmd" || true; } 2>/dev/null; } | tee "${to}.log") | tee "${to}.list" | wc -l)
# fi

_exists() {
	while IFS= read -r line ; do
	  test -e "$line" || test -L "$line" || continue
	  echo "$line"
	done
}


_evaluate_find() { _exists | tee "${to}.list" | wc -l; }

_evaluate_grep() { awk -F\: '{print $1}' | tee "$1" | wc -l; }

_parse_entries() { grep -Po "$1 -> \[\K.*(?=\])" "$2" | sed 's|[\,]\s*|\n|g;s|[\"]||g'; }

# Unless the search was intended to include the .claude directory, ensure it is ignored (avoids high likelihood of noise polution)
if [[ "$Cmd" == "grep" && "$cmd" != *".claude"* ]]; then
  cmd="${cmd//grep /grep --exclude-dir=.claude }"
fi

declare -i fc=$({ { eval "$cmd" || true; } 2> >(tee "${to}.err" >&2); } | tee "${to}.log" | _evaluate_${Cmd} "${to}.list")

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
    # INDEX.md keys are repo-relative and unprefixed. Strip the absolute prefix, then the leading './'
    # that a recursive search rooted at the cwd stamps onto every path (e.g. `grep -r <pat> .`)
    rel="${files[f]#*${REPO_ROOT:-${PROJECT_ROOT:-${REPO_NAME:-$PROJECT_NAME}}}\/}"
    [[ "$rel" != .\/* ]] || rel="${rel:2}"
    while read line ; do
      [[ ! -e "${KnowledgeBase}/entries/${line}" || "${entries[*]}" == *"$line"* ]] || entries[${#entries[@]}]="$line"
    done < <(_parse_entries "$rel" "${KnowledgeBase}/INDEX.md" 2>/dev/null)
  done
fi


# Process for org knowledge
if [[ -d "$OrgKnowledge" ]]; then
  for ((f=0;f<${#files[@]};f++)); do
    # Same normalization as the repo|project lookup above — org INDEX.md keys are unprefixed too
    rel="${files[f]#*${ORG_DIR}\/}"
    [[ "$rel" != .\/* ]] || rel="${rel:2}"
    while read line ; do
      [[ ! -e "${OrgKnowledge}/entries/${line}" || "${org_entries[*]}" == *"$line"* ]] || org_entries[${#org_entries[@]}]="$line"
    done < <(_parse_entries "$rel" "${OrgKnowledge}/INDEX.md" 2>/dev/null)
  done
fi



# —————————————————————————————————————————————————————————————————————————————————
# OUTPUT SECTION
# ————————————————————————————————————————————————————————————————————————————————

# count the total resulting matches
declare -i this_many=$((${#entries[@]} + ${#org_entries[@]})) 2>/dev/null || declare -i this_many=0

# guard impossible state
if ((fc == 0 && this_many != 0)); then
  knerr 'tool_call resulted in no results but somehow we have > 0 matching knowledge entries.'
  exit 1
fi

# 'fc' (file count) -> { tool_call stdout | wc -l }
if ((fc > 0)); then
  # Prepare how the results will be shown to the model
  if ((fc > 80)); then
    new_cmd="echo \"=== COMMAND ===\"; echo \"$cmd\"; echo \"\"; echo \"=== RESULTS ===\"; wc -l \"${to}.log\"; echo \"(large output)\""
  else
    new_cmd="cat \"${to}.log\""
  fi

  # Prepare the additionalContext (conditionally delivered alongside the results)
  if ((this_many > 0)); then
    # Build additionalConetxt Output: surface any matched knowledge entries via additionalContext
    ctx_json="{}"
    # Build additionalContext for any matched repo|project entries
    for ((i=0;i<${#entries[@]};i++)); do
      ctx_json=$(printf '%s' "$ctx_json" | jq --arg e "${KnowledgeBase}/entries/${entries[i]}" '.knowledge += [$e]')
    done
    # Build additionalContext for any matched org entries
    for ((i=0;i<${#org_entries[@]};i++)); do
      ctx_json=$(printf '%s' "$ctx_json" | jq --arg e "${OrgKnowledge}/entries/${org_entries[i]}" '.org_knowledge += [$e]')
    done
  
    if [[ "$ctx_json" != "{}" ]]; then
      # --- DEBUG ---
      #       knerr 2 "knowledge hook output mode: 2
      # (tool_call produced output AND surfaced $this_many entries)"
      # ---  ---  ---
      # WITH ADDITIONAL CONTEXT
      sysmsg="(Surfaced $this_many Knowledge Entries)"
      # additionalContext must be a string — serialize the JSON object
      ctx_str=$(printf '%s' "$ctx_json" | jq -r 'to_entries | map("[\(.key)]\n\(.value | join("\n"))") | join("\n\n")')
      printf '%s' "$Input" | jq \
        --arg msg "$sysmsg" \
        --arg ctx "$ctx_str" \
        --arg nc "$new_cmd" '{
        systemMessage: $msg,
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "allow",
          additionalContext: $ctx,
          updatedInput: (.tool_input | .command = $nc)
        }
      }'
      exit 0
    else
      knerr 'additionalContext builders are likely busted.'
    fi
  fi
  # --- DEBUG ---
  #   knerr 1 "knowledge hook output mode: 1
  # (tool_call has results, no matching entries)"
  # ---  ---  ---
  # Grep had results but no knowledge entries matched
  # — replay cached output instead of running the command a second time.
  printf '%s' "$Input" | jq \
    --arg nc "cat \"${to}.log\"" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: (.tool_input | .command = $nc)
    }
  }'
else
  # --- DEBUG ---
  #   knerr 0 "knowledge hook output mode: 0
  # (tool_call produced no output)"
  # ---  ---  ---
  # We're trying to throw in the additional niceity of not allowing the harness to re-run an unnecessary command.
  # There are a number of philosophical concerns that apply here, but even if we sit those aside, there's still no denying
  #  that Claude's go-to strategy is to perform a totally unecessarily broad call to find or grep -r
  #
  # We have observed this problem getting worse with harness "updates" and model newer versions.
  # There seems to be no reliable way to prevent claude (or perhaps Anthropic's harness) from perfoming a call to  ls  or  find  whenever a file is metioned.
  # This happens regardless of supplying the exact absolute path, and the '@' prefix only seems to work about 10% of the time,
  #                                            (but Claude will still go looking for it later in the same session anyway so...)
  #
  # * This wouldn't be so terrible if the clanker would at least begin by applying what you said to it in its search.
  #   If you gave an absolute path, (we can argue about whether it should even check first in such situations to begin with, but)
  #                                 it should limit its search to literally that file and then walk up the directory hierarchy based opn the path that YOU provided to it.
  #                                 Otherwise, it shold begin from cwd. In our experience it usually just calls find on your home directory.
  #   This else-clause attempts to reduce that strain.
  printf '%s' "$Input" | jq \
    --arg msg "(knowledge::pre-search.sh): tool_call results were empty" '{
    systemMessage: $msg,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: "No output",
      updatedInput: (.tool_input | .command = "false")
    }
  }'
fi

# —————————————————————————————————————————————————————————————————————————————————
# DEBUGGING
# —————————————————————————————————————————————————————————————————————————————————
# cd ~/Workspaces/night-district/night-district-core
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "grep -RIns \"Stickers\"" } }' | .claude/hooks/knowledge/pre-search.sh
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "find -type f -iwholename \"*config/routes/hq.rb\"" } }' | .claude/hooks/knowledge/pre-search.sh
#
# Or use --test and pass it in directly:
# .claude/hooks/knowledge/pre-search.sh --test 'grep -RIns "Stickers"'
