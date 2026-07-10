#!/usr/bin/env bash
# Raw side-by-side: shows the exact input, exact command, and exact output
# for both scripts on every test case. Copy any block and run it yourself.

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE="$SCRIPT_DIR/../.claude/hooks/lib/parse-search.sh"
KNOWLEDGE="$SCRIPT_DIR/../.claude/hooks/knowledge.sh"

N=0

run_both() {
  local cmd="$1"
  ((N++))

  local json
  json=$(jq -n --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')

  echo "════════════════════════════════════════════════════════════════"
  echo "TEST $N"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "INPUT COMMAND:"
  echo "  $cmd"
  echo ""
  echo "── parse-search.sh ──"
  echo "RUN: echo '$cmd' | bash $PARSE"
  echo "OUTPUT:"
  local p_out
  p_out=$(echo "$cmd" | bash "$PARSE" 2>&1) || true
  if [[ -z "$p_out" ]]; then
    echo "  (empty - no output)"
  else
    echo "$p_out" | sed 's/^/  /'
  fi
  echo ""
  echo "── knowledge.sh ──"
  echo "RUN: printf '%s' '$json' | bash $KNOWLEDGE"
  echo "JSON INPUT:"
  echo "$json" | sed 's/^/  /'
  echo "OUTPUT:"
  local k_out
  k_out=$(printf '%s' "$json" | bash "$KNOWLEDGE" 2>&1) || true
  if [[ -z "$k_out" ]]; then
    echo "  (empty - no output)"
  else
    echo "$k_out" | sed 's/^/  /'
  fi
  echo ""
  echo ""
}

# ── recursive grep: one per distinct parsing path ──
run_both 'grep -r "ActionCable" app/'
run_both 'grep -rn --include="*.py" "import flask" src/'
run_both 'grep -rn -C3 "def process" app/'
run_both 'grep -rn -e "pattern1" -e "pattern2" src/'
run_both 'grep -R "WebSocket" lib/'
run_both 'grep -Rn "config.cache" .'

# ── rg: one per distinct parsing path ──
run_both 'rg "ActionCable" app/'
run_both 'rg ActionCable app/'
run_both 'rg -g "*.ts" "interface Props" src/'
run_both 'rg -t py "import" src/'
run_both 'rg --pcre2 "(?<=class\s)\w+" app/'
run_both 'rg -F "std::vector<int>" src/'
run_both 'rg -U "fn\n\s+main" src/'
run_both 'rg "def (create|update|destroy)" app/controllers/'

# ── ag / ack: one each ──
run_both "ag 'render_template' app/views/"
run_both 'ack "def initialize" app/'

# ── non-search commands ──
run_both 'ls -la'
run_both 'npm install express'

# ── non-recursive grep ──
run_both 'grep "pattern" file.txt'
run_both 'echo "some text" | grep "pattern"'
run_both 'ps aux | grep python'
run_both 'env | grep PATH'

# ── egrep / fgrep ──
run_both 'egrep "TODO|FIXME" file.txt'
run_both 'egrep -r "TODO|FIXME" .'
run_both 'fgrep -r "literal" src/'

# ── special characters as literals in patterns ──
run_both 'grep -rn "Class::Method" app/'
run_both 'grep -rn "package.module" app/'
run_both 'grep -rn "org.example.MyClass" app/'
run_both 'grep -rn "@decorator" app/'
run_both 'grep -rn "$variable" app/'
run_both 'grep -rn "import flask" src/'
run_both 'grep -rn "def self.find_by" app/'
run_both 'grep -rn "has_many :orders" app/models/'
run_both 'grep -rn "TODO:" app/'
run_both 'grep -rn "user->name" app/'
run_both 'grep -rn "#include" app/'
run_both 'grep -rn "//nolint" app/'
run_both 'grep -rn "config.redis" app/'

# ── rg -F: metacharacters as literals ──
run_both 'rg -F "a+b" src/'
run_both 'rg -F "foo|bar" src/'
run_both 'rg -F "std::cout << x" src/'
run_both 'rg -F "a]b" src/'

# ── regex patterns ──
run_both 'grep -rn "^def process" app/'
run_both 'grep -rn "TODO.*FIXME" app/'
run_both 'grep -rn "user\." app/'

# ── find ──
run_both 'find . -name "*.rb"'
run_both 'find . -name "Dockerfile"'
run_both 'find src -name "*.tsx" -o -name "*.ts"'
run_both 'find . -iname "readme*"'
run_both 'find . -wholename "*/.claude/*"'
run_both 'find . -path "*/migrations/*"'
run_both 'find . -type f -name "*.log" -mtime -7'

# ── fd ──
run_both 'fd "controller"'
run_both 'fd -e py "test"'
run_both 'fd -t f "config"'
run_both 'fd --hidden "env"'
run_both 'fd -g "*.ts" src/'

# ── edge cases ──
run_both 'grep -rn "" app/'
run_both 'grep -rn "a" app/'
run_both 'rg "café" src/'
run_both 'grep -rn "日本語" src/'
run_both 'ast-grep -p "console.log($$$)" src/'

# ── flag-eating ──
run_both 'grep -rn -m 5 "pattern" app/'
run_both 'rg -A 3 -B 3 "pattern" src/'
run_both 'grep -rn -f patterns.txt app/'

# ── compound / chained ──
run_both 'grep -rn "TODO" app/ | wc -l'
run_both 'rg "error" src/ && echo "found"'
