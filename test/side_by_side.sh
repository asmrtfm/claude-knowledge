#!/usr/bin/env bash
# Side-by-side: runs every test command through BOTH actual scripts and
# shows their exact raw output. No rewrites, no harnesses, no copies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE="$SCRIPT_DIR/../.claude/hooks/lib/parse-search.sh"
KNOWLEDGE="$SCRIPT_DIR/../.claude/hooks/knowledge.sh"

# knowledge.sh expects JSON with tool_name=Bash and tool_input.command=<cmd>
# It outputs JSON with the query baked into updatedInput.command, or exits 0 (empty).
# We extract just the query from the grep pattern it builds: grep -liIRs "<query>" ...
run_knowledge() {
  local cmd="$1"
  local json
  json=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
  local out
  out=$(printf '%s' "$json" | bash "$KNOWLEDGE" 2>/dev/null) || true
  if [[ -z "$out" ]]; then
    echo ""
    return
  fi
  # Extract the query from: grep -liIRs "<query>" <paths>; echo "---"; <original cmd>
  # The query sits between the first pair of escaped quotes in the new_cmd
  local new_cmd
  new_cmd=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null) || true
  if [[ -z "$new_cmd" ]]; then
    echo "[no updatedInput]"
    return
  fi
  # Pull the query out: it's between grep -liIRs " and the next "
  local query
  query=$(echo "$new_cmd" | sed -n 's/.*grep -liIRs "\([^"]*\)".*/\1/p')
  echo "$query"
}

run_parse() {
  echo "$1" | bash "$PARSE" 2>/dev/null || true
}

W_CMD=55
W_OUT=35

header() {
  echo ""
  echo "  ── $1 ──"
  printf "  %-${W_CMD}s  %-${W_OUT}s  %s\n" "COMMAND" "parse-search.sh" "knowledge.sh"
  printf "  %-${W_CMD}s  %-${W_OUT}s  %s\n" \
    "$(printf '%0.s─' $(seq 1 $W_CMD))" \
    "$(printf '%0.s─' $(seq 1 $W_OUT))" \
    "$(printf '%0.s─' $(seq 1 $W_OUT))"
}

row() {
  local cmd="$1"
  local p_out k_out
  p_out=$(run_parse "$cmd")
  k_out=$(run_knowledge "$cmd")
  [[ -z "$p_out" ]] && p_out="(empty)"
  [[ -z "$k_out" ]] && k_out="(empty)"
  printf "  %-${W_CMD}s  %-${W_OUT}s  %s\n" "$cmd" "$p_out" "$k_out"
}

echo "═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
echo "  SIDE-BY-SIDE: actual parse-search.sh vs actual knowledge.sh"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"

header "grep -r (recursive grep)"
row 'grep -r "ActionCable" app/'
row "grep -r 'order_status' app/"
row 'grep -rn "ActionCable" app/'
row 'grep -rni "ActionCable" app/'
row 'grep -rl "TODO" src/'
row 'grep -rn --include="*.py" "import flask" src/'
row 'grep -rn --exclude-dir=node_modules "useState" .'
row 'grep -rn -C3 "def process" app/'
row 'grep -rn -A5 -B2 "class User" app/models/'
row 'grep -rnw "REDIS_URL" .'
row 'grep -rn --color=never "authenticate!" app/controllers/'
row 'grep -rn -e "pattern1" -e "pattern2" src/'

header "grep -R (recursive, follow symlinks)"
row 'grep -R "WebSocket" lib/'
row 'grep -Rn "config.cache" .'
row 'grep -Rni "secret_key" .'

header "rg (ripgrep)"
row 'rg "ActionCable" app/'
row "rg 'order_status' app/"
row 'rg ActionCable app/'
row 'rg "WebSocket" --type ruby'
row 'rg -i "fixme" .'
row 'rg -l "TODO" src/'
row 'rg -w "User" app/models/'
row 'rg --hidden "API_KEY" .'
row 'rg -g "*.ts" "interface Props" src/'
row 'rg -t py "import" src/'
row 'rg --pcre2 "(?<=class\s)\w+" app/'
row 'rg -c "TODO" .'
row 'rg -F "std::vector<int>" src/'
row 'rg --json "pattern" src/'
row 'rg -U "fn\n\s+main" src/'
row 'rg "def (create|update|destroy)" app/controllers/'

header "ag (the silver searcher)"
row "ag 'render_template' app/views/"
row 'ag "ActionMailer" app/'
row 'ag -l "TODO" .'
row 'ag -w "User" app/'
row 'ag --hidden "SECRET" .'

header "ack"
row 'ack "def initialize" app/'
row "ack 'validates' app/models/"
row 'ack --type=ruby "module" lib/'

header "non-search commands"
row 'ls -la'
row 'cat README.md'
row 'echo "hello world"'
row 'mkdir -p src/components'
row 'cd /tmp && pwd'
row 'npm install express'
row 'git log --oneline'
row 'python3 manage.py migrate'
row 'docker ps -a'
row 'curl -s https://example.com'

header "non-recursive grep"
row 'grep "pattern" file.txt'
row 'grep -n "error" log.txt'
row 'grep -c "TODO" file.py'
row 'grep -l "import" file1.py file2.py'
row 'echo "some text" | grep "pattern"'
row 'cat file.txt | grep -i "error"'
row 'ps aux | grep python'
row 'env | grep PATH'
row 'git log | grep "fix"'
row 'history | grep "deploy"'

header "egrep / fgrep"
row 'egrep "TODO|FIXME" file.txt'
row 'fgrep "literal string" file.txt'
row 'egrep -r "TODO|FIXME" .'
row 'fgrep -r "literal" src/'

header "simple identifiers"
row 'grep -rn "ActionCable" app/'
row 'grep -rn "snake_case_name" app/'
row 'grep -rn "camelCaseName" app/'
row 'grep -rn "SCREAMING_SNAKE" app/'
row 'grep -rn "kebab-case-name" app/'
row 'grep -rn "Class::Method" app/'
row 'grep -rn "package.module" app/'
row 'grep -rn "org.example.MyClass" app/'
row 'grep -rn "@decorator" app/'
row 'grep -rn "$variable" app/'

header "multi-word / phrase patterns"
row 'grep -rn "import flask" src/'
row 'grep -rn "class UserController" app/'
row 'grep -rn "def self.find_by" app/'
row 'grep -rn "has_many :orders" app/models/'

header "special characters in search terms"
row 'grep -rn "TODO:" app/'
row 'grep -rn "user->name" app/'
row 'grep -rn "#include" app/'
row 'grep -rn "//nolint" app/'
row 'rg -F "a]b" src/'

header "pattern mangling (regex stripping)"
row 'grep -rn "process_order" app/'
row 'grep -rn "config.redis" app/'
row 'grep -rn "user.email" app/'
row 'rg -F "std::cout << x" src/'
row 'rg -F "a+b" src/'
row 'rg -F "foo|bar" src/'
row 'rg -F "file.txt" src/'

header "regex patterns"
row 'grep -rn "^def process" app/'
row 'grep -rn "TODO.*FIXME" app/'
row 'rg "(create|update|destroy)" app/'
row 'grep -rn "user\." app/'

header "find -name"
row 'find . -name "*.rb"'
row 'find . -name "Dockerfile"'
row 'find . -name "*.test.ts"'
row 'find . -name "config.*"'
row "find . -name '*.py'"
row 'find src -name "*.tsx" -o -name "*.ts"'

header "find -iname"
row 'find . -iname "readme*"'
row 'find . -iname "*.JSON"'

header "find other predicates"
row 'find . -wholename "*/.claude/*"'
row 'find . -path "*/migrations/*"'
row 'find . -type f -name "*.log" -mtime -7'
row 'find . -name "*.pyc" -delete'

header "fd"
row 'fd "controller"'
row 'fd controller'
row 'fd -e py "test"'
row 'fd -t f "config"'
row 'fd --hidden "env"'
row 'fd -g "*.ts" src/'

header "edge cases"
row 'grep -rn "" app/'
row 'rg "" src/'
row 'grep -rn "a" app/'
row 'grep -rn "AB" app/'
row 'rg "café" src/'
row 'rg "naïve" src/'
row 'grep -rn "日本語" src/'
row 'ast-grep -p "console.log($$$)" src/'

header "flag-eating"
row 'grep -rn -m 5 "pattern" app/'
row 'grep -rn --max-count=5 "pattern" app/'
row 'rg -m 5 "pattern" src/'
row 'rg -A 3 -B 3 "pattern" src/'
row 'rg --max-columns 200 "pattern" src/'
row 'grep -rn -f patterns.txt app/'

header "compound / chained commands"
row 'grep -rn "TODO" app/ | wc -l'
row 'grep -rn "FIXME" app/ | sort | uniq'
row 'rg "error" src/ && echo "found"'
row 'rg "warn" src/ || true'

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
