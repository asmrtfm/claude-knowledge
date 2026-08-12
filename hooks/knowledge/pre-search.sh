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
#           AVAILABLE ACTION NODES (sequencable) - almost like a minimal n8n
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
#   1. Run claude's command, capture the output, parse any file paths.
#   2. If the paths are absolute, strip them to be relative to ${REPO_ROOT:-$PROJECT_ROOT}
#   3. For each resulting relative file path, look it up in .claude/knowledge/INDEX.md and collect any linked knowledge entries.
#   4. Do the same for the org knowledge if the repo is registered with an org.
#   5. Surface the matched knowledge entries via `"additionalContext": { "knowledge":[<entries ...>], "org_knowledge":[<org_entries ...>] }`
#   ^. NOTE: We tried everything but claude always ignores the additionalContext.
#            We tried creating a rule, we even tried to let claude tell us what to do that it would not ignore... it ignored it.
#            We tried adding skills that would trigger specificaly alongside knowledge entries being surfaced, it ignored it...
#            This really stings because, although claude-opus-5 is an unuseable regression/abomination, it actually did not ignore the additionalContext.
#            Here's to hoping they release a 5.1 that fixes the regressions but keeops that one noticable gain...
#            So, for now, we do everything we can avoid interuptig claude,
#             but alas when there are matching entries it has yet to consider, we have no choice but to tell it to pause and consider them.
#
#            Leaving these notes in here as a reminder that the whole point - our assertion - is that prompt injection is ALWAYS the worst option.
#                                                                                                                         ... but it is AN option.

if [[ "${1,,}" == +(\-)'test' ]]; then
  # Prefer positional args when present; fall back to stdin for piped input
  if (($# > 1)); then
    cmd="${@:2}"
  elif [[ ! -t 0 ]]; then
    cmd=$(cat)
  else
    echo "[WARN] no input"
    cmd=""
  fi
  Input=$(jq -n --arg tu "toolu_test$(date '+%s')" --arg c "$cmd" '{ "tool_use_id": $tu, "tool_input": { "command": $c } }')
else
  Input=$(cat)
  cmd=$(jq -r '.tool_input.command // ""' <<<"$Input")
fi


# Only gate commands that invoke a recursive grep (any variant: grep, egrep, fgrep, ugrep, rgrep)
#                                                  ( intentionally avoids matching on  ast-grep )
_is_recursive() {
  [[ "$*" == ?([a-z])@('grep'|'rg'|'ripgrep')+([[:space:]])+(-)*([[:alnum:]])@([rR])* || \
     "$*" == *\|+([[:space:]])?([a-z])@('grep'|'rg'|'ripgrep')+([[:space:]])+(-)*([[:alnum:]])@([rR])* || \
     "$*" == @('rg'|'ripgrep')* \
  ]]
}

# Only intercept search commands
case "$cmd" in
  *'ast-grep'*) exit 0 ;;
  *'find '*) Cmd="find" ;;
  *'grep '*) _is_recursive "$cmd" || exit 0; Cmd="grep" ;;
  *'rg '*) Cmd="rg" ;; # TODO: verify whether or not we'll need dedicated handling or if we can just lump rg in with grep
  *) exit 0 ;;
esac


. "${BASH_SOURCE[0]%\/*}/lib/resolve-env.sh"
_set_repo_root
_set_org_dir

[[ -n $CLAUDE_SESSION_ID ]] || CLAUDE_SESSION_ID=$(jq -r '.session_id // .sessionId // ""' <<<"$Input")
if [[ -z $CLAUDE_SESSION_ID ]]; then
  printf '%b%s%b\n' '\033[1;31m' "CLAUDE_SESSION_ID could not be set" '\033[0m' >&2
  printf '%s' "$Input" | jq \
    --arg msg "Hey boss. Looks like things done changed. You'll probably want to disable the knowledge hooks for the time being..." '{
    systemMessage: $msg,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      additionalContext: "STOP. Make sure the user read the system message."
    }
  }'
  exit 2
fi

# Step 0: create an output file in which to capture the output of their command. use the toolcall_id as the basename.
tool_use_id=$(jq -r '.tool_use_id // ""' <<<"$Input")

# Ensure local cache is around
CLAUDE_SESSION_CACHE="${CLAUDE_LOCAL_CACHE:-$(nearest -d .claude --from "${BASH_SOURCE[0]}")/cache}"
[[ "$CLAUDE_SESSION_CACHE" == *"$CLAUDE_SESSION_ID"* ]] || CLAUDE_SESSION_CACHE="${CLAUDE_SESSION_CACHE}/${CLAUDE_SESSION_ID}"
mkdir -p "$CLAUDE_SESSION_CACHE"
to="${CLAUDE_SESSION_CACHE}/${tool_use_id}"
# echo "to: ${to}"


_exists() {
	while IFS= read -r line ; do
	  test -e "$line" || test -L "$line" || continue
	  echo "$line"
	done
}

_evaluate_find() { _exists | tee "${to}.list" | wc -l; }

_evaluate_grep() { awk -F\: '{print $1}' | tee "$1" | wc -l; }

_parse_entries() { grep -Po "$1 -> \[\K.*(?=\])" "$2" | sed 's|[\,]\s*|\n|g;s|[\"]||g'; }

#*find*(+([[:space:]])*(\-[![:space:]]))+([[:space:]])+(*([[:space:]])*(@(\'|\")|\-|\.|\/|\*|\_)+([[:alnum:]]))+([[:space:]]|\$IFS)*([[:space:]])}"

# --- INTENTIONALITY ---
# This is where you could iterate over a configurable set of paths that
#  you want searches to avoid in all circumstances OTHER THAN when they ARE the specific target.
# In other words, unless Claude is specifically searching for something in .git, or .claude, I want them automatically ignored.
#
# For now, we're just doing .claude
#
if [[ -f "${BASH_SOURCE[0]%\/*}/.ignored" ]]; then
  orig_cmd="$cmd"
  readarray -t IGNORE_DIRS < "${BASH_SOURCE[0]%\/*}/.ignored"
fi

ignore_str=""
for ((d=0;d<${#IGNORE_DIRS[@]};d++)); do
  if [[ "$cmd" != *"${IGNORE_DIRS[d]}"* ]]; then
    case "$Cmd" in
    "grep") ignore_str+="--exclude-dir=${IGNORE_DIRS[d]} " ;;
    "find") ignore_str+="-not -path '*${IGNORE_DIRS[d]}*' " ;;
    *) continue
    esac
  fi
done

# TODO: handle `grep ... [';' '||' '&&'] grep ...`

shopt -s extglob

_is_compound() { [[ "$cmd" == *@('&&'|'||'|';')* ]]; }

_back_len() {
  # {
  #   echo "---"
  #   echo " split:"
  #   sed 's|[\ ][\-]|\n\-|g;s|[\ ][\|][\ ]|\n\|\ |g' <<<"$cmd"
  #   echo "---"
  # } >&2
  local -i p=0
  local part=""
  local -a parts=()
  while IFS= read -r line; do
    parts[${#parts[@]}]="$line"
    if [[ ${#parts[0]} -gt 8 || "${parts[-1]}" != "find"* ]]; then
      p=${#parts[@]}
      break
    fi
  done < <(sed 's|[\ ][\-]|\n\-|g;s|[\ ][\|][\ ]|\n\|\ |g' <<<"$cmd")
  [[ "${parts[0]}" == "find"* ]] || return 1
  part="$cmd"
  # shopt -s extglob
  for ((n=0;n<p;n++)); do
    part="${part#*${parts[n]}*([[:space:]])}"
  done
  # shopt -u extglob
  echo "$part"
}

_take_apart() {
  local -i p=0
  local part=""
  local -a parts=()
  while IFS= read -r line; do
    parts[${#parts[@]}]="$line"
    if [[ ${#parts[0]} -gt 8 || "${parts[-1]}" != "find"* ]]; then
      p=${#parts[@]}
      break
    fi
  done < <(sed 's|[\ ][\-]|\n\-|g;s|[\ ][\|][\ ]|\n\|\ |g' <<<"$*")
  [[ "${parts[0]}" == "find"* ]] || return 1
  part="$*"
  for ((n=0;n<p;n++)); do
    part="${part#*${parts[n]}*([[:space:]])}"
  done
  echo "$part"
}

_handle_compound_finds() {
  shopt -s extglob
  local -a segs=()
  readarray -t segs < <(echo "${cmd//*([[:space:]])@('&&'|'||'|';')*([[:space:]])/$'\n'}" )
  for ((s=0;s<${#segs[@]};s++)); do
    if [[ "${segs[s]}" == *"find "* ]]; then
      back="$(_take_apart "${segs[s]}")"
      front="${segs[s]:: -$((${#back} - 1))}"
      seg="${front} ${ignore_str}${back}"
      cmd=${cmd/"${segs[s]}"/"$seg"}
      unset front back seg 2>/dev/null
    fi
  done
}

if ((${#ignore_str} > 0)); then
  case "$Cmd" in
  "grep") cmd="${cmd//grep /grep ${ignore_str}}" ;;
  "find")
    if _is_compound; then
      _handle_compound_finds
    else
      back="$(_back_len)"
      front="${cmd:: -$((${#back} - 1))}"
      cmd="${front} ${ignore_str}${back}"
      unset front back 2>/dev/null
    fi ;;
  esac
fi

[[ "$Cmd" != 'rg' ]] || Cmd='grep'


# echo "running:"
# echo "$cmd"
declare -i fc=$({ { eval "${cmd}" || true; } 2> >(tee "${to}.err" >&2); } | tee "${to}.log" | _evaluate_${Cmd} "${to}.list")
# declare -i fc=$({ { eval "${cmd//\'/\"}" || true; } 2> >(tee "${to}.err" >&2); } | tee "${to}.log" | _evaluate_${Cmd} "${to}.list")

if [[ "${DEBUG:-false}" == "true" ]]; then
  sysmsg="(knowledge::pre-search.sh - no output from tool_call):\n${cmd}"
  no_dice() {
    printf '%s' "$Input" | jq \
      --arg nc "cat '${to}.log'" \
      --arg msg "$sysmsg" '{
      systemMessage: $msg,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: "No output",
        updatedInput: (.tool_input | .command = $nc)
      }
    }'
  }
else
  sysmsg="(knowledge::pre-search.sh): tool_call results were empty"
  no_dice() {
    printf '%s' "$Input" | jq \
      --arg msg "$sysmsg" '{
      systemMessage: $msg,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: "No output",
        updatedInput: (.tool_input | .command = "false")
      }
    }'
  }
fi

if [[ ! -s "${to}.list" ]]; then
  no_dice
  exit 0
fi


# --------- --------- ---------
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
if EnvRC="$(nearest -x .envrc --from "${BASH_SOURCE[0]%\/*}")"; then
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

# The session's already-read knowledge entries (written by post-read.sh)
AlreadyRead="${CLAUDE_SESSION_CACHE}/reads.log"

# Process for repo|project knowledge
if [[ -d "$KnowledgeBase" ]]; then
  for ((f=0;f<${#files[@]};f++)); do
    # INDEX.md keys are repo-relative and unprefixed. Strip the absolute prefix, then the leading './'
    # that a recursive search rooted at the cwd stamps onto every path (e.g. `grep -r <pat> .`)
    rel="${files[f]#*${REPO_ROOT:-${PROJECT_ROOT:-${REPO_NAME:-$PROJECT_NAME}}}\/}"
    [[ "$rel" != .\/* ]] || rel="${rel:2}"
    while read line ; do
      # Skip entries that don't exist, are already queued, or were already read this session
      [[ -e "${KnowledgeBase}/entries/${line}" && "${entries[*]}" != *"$line"* ]] || continue
      [[ ! -f "$AlreadyRead" ]] || { grep -qsFx "${KnowledgeBase}/entries/${line}" "$AlreadyRead" >/dev/null && continue; }
      entries[${#entries[@]}]="$line"
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
      # Skip entries that don't exist, are already queued, or were already read this session
      [[ -e "${OrgKnowledge}/entries/${line}" && "${org_entries[*]}" != *"$line"* ]] || continue
      [[ ! -f "$AlreadyRead" ]] || { grep -qsFx "${OrgKnowledge}/entries/${line}" "$AlreadyRead" >/dev/null && continue; }
      org_entries[${#org_entries[@]}]="$line"
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

# --------- --------- ---------
# 'fc' (file count) -> { tool_call stdout | wc -l }
if ((fc > 0)); then
  # Prepare how the results will be shown to the model
  if ((fc > 80)); then # \"${orig_cmd@Q}\"
    new_cmd="echo '=== COMMAND ==='; echo \"${orig_cmd}\"; printf '\n%s\n' '=== RESULTS ==='; wc -l '${to}.log'; echo '(large output)'"
  else
    new_cmd="cat '${to}.log'"
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
        --arg ctx "PAUSE. Make a relevance judgment based on the paths of the following knowledge entries. The paths are structured \`<subject-matter>/<title>\`. IF an entry seems related to your current task, then do NOT ignore it. You MUST acknowledge that you read this message by calling out any ignored knowledge entries that surfaced.\n${ctx_str}" \
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
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '%s' "$Input" | jq \
      --arg msg "$sysmsg" \
      --arg nc "cat '${to}.log'" '{
      systemMessage: $msg,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: (.tool_input | .command = $nc)
      }
    }'
  else
    printf '%s' "$Input" | jq \
      --arg nc "cat '${to}.log'" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: (.tool_input | .command = $nc)
      }
    }'
  fi
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
  no_dice
fi

# —————————————————————————————————————————————————————————————————————————————————
# DEBUGGING
# —————————————————————————————————————————————————————————————————————————————————
# cd ~/Workspaces/night-district/night-district-core
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "grep -RIns \"Stickers\"" } }' | .claude/hooks/knowledge/pre-search.sh
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "find -type f -iwholename \"*config/routes/hq.rb\"" } }' | .claude/hooks/knowledge/pre-search.sh

# testing  this one problematic
# jq -n '{ "tool_use_id": "toolu_123", "tool_input": { "command": "cd /home/me/Workspaces/night-district && echo \"=== extz/ (pure Ruby) ===\" && find extz -type f -name '*.rb' | sort && echo \"\" && echo \"=== extz-rails/ (Rails-dependent) ===\" && find extz-rails -type f -name '*.rb' | sort", "description": "Show final tree of both packages" }' | .claude/hooks/knowledge/pre-search.sh


# Or use --test and pass it in directly:
# .claude/hooks/knowledge/pre-search.sh --test 'grep -RIns "Stickers"'
