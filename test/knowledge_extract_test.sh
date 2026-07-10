#!/usr/bin/env bash
# Runs the same test cases as parse_search_test.sh but against knowledge.sh's
# term extraction logic. This lets us compare both scripts side by side.
#
# knowledge.sh is a PreToolUse hook — it takes JSON on stdin and outputs JSON.
# Its `exit 0` on line 3 disables it, and it hardcodes repo paths. We source
# the extraction logic directly by wrapping it in a harness that:
#   1. Skips the early exit and hook plumbing
#   2. Feeds in the command
#   3. Prints the extracted terms

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
HOOK="$SCRIPT_DIR/../.claude/hooks/knowledge.sh"

# Build a harness that extracts just the term-parsing logic from knowledge.sh.
# We can't source it directly because of the `exit 0` and JSON I/O, so we
# extract lines 20-92 (the case/extraction block) and wrap them.
HARNESS=$(mktemp)
trap 'rm -f "$HARNESS"' EXIT

cat > "$HARNESS" << 'HARNESS_EOF'
#!/usr/bin/env bash
# Harness: feeds a raw command into knowledge.sh's extraction logic
cmd="$1"

declare -ga terms=()

find_flag_values() {
  local flag="$1"
  local text="$2"
  while [[ "$text" =~ -${flag}[[:space:]]+([^[:space:]]+) ]]; do
    local val="${BASH_REMATCH[1]}"
    val="${val//\"/}"
    val="${val//\'/}"
    val="${val//\*/}"
    [[ -n "$val" ]] && terms+=("$val")
    text="${text#*"${BASH_REMATCH[0]}"}"
  done
}

# Gate: only intercept search commands (matching knowledge.sh's case block)
case "$cmd" in
  *'ast-grep'*) exit 0 ;;
  *'find '*) ;;
  *'grep '*) ;;
  *'rg '*) ;;
  *) exit 0 ;;
esac

case "$cmd" in
  *'find '*)
    for flag in name iname wholename iwholename path ipath; do
      find_flag_values "$flag" "$cmd"
    done
    ;;
  *'grep '*|*'rg '*)
    local_cmd="${cmd##*grep }"
    [[ "$cmd" == *'rg '* ]] && local_cmd="${cmd##*rg }"
    for part in $local_cmd; do
      [[ "$part" == -* ]] && continue
      [[ -e "$part" || "$part" == "." || "$part" == "./" ]] && continue
      part="${part//\"/}"
      part="${part//\'/}"
      [[ -n "$part" ]] && terms+=("$part")
      break
    done
    ;;
esac

# Output the terms space-separated (like parse-search.sh does)
echo "${terms[*]}"
HARNESS_EOF
chmod +x "$HARNESS"

# Helper: run a command through the knowledge.sh extraction harness
extract() {
  local output
  output=$(bash "$HARNESS" "$1" 2>/dev/null)
  # Trim whitespace
  echo "$output" | xargs 2>/dev/null || echo ""
}

echo "── knowledge.sh extraction logic ──"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 1: Commands that SHOULD be intercepted (recursive/codebase search)
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── grep -r (recursive grep) ──"

result=$(extract 'grep -r "ActionCable" app/')
assert_eq "grep -r double-quoted" "ActionCable" "$result"

result=$(extract "grep -r 'order_status' app/")
assert_eq "grep -r single-quoted" "order_status" "$result"

result=$(extract 'grep -rn "ActionCable" app/')
assert_eq "grep -rn" "ActionCable" "$result"

result=$(extract 'grep -rni "ActionCable" app/')
assert_eq "grep -rni" "ActionCable" "$result"

result=$(extract 'grep -rl "TODO" src/')
assert_eq "grep -rl (list files)" "TODO" "$result"

result=$(extract 'grep -rn --include="*.py" "import flask" src/')
assert_eq "grep -rn --include with pattern" "import flask" "$result"

result=$(extract 'grep -rn --exclude-dir=node_modules "useState" .')
assert_eq "grep -rn --exclude-dir" "useState" "$result"

result=$(extract 'grep -rn -C3 "def process" app/')
assert_eq "grep -rn with context flag" "def process" "$result"

result=$(extract 'grep -rn -A5 -B2 "class User" app/models/')
assert_eq "grep -rn with before/after context" "class User" "$result"

result=$(extract 'grep -rnw "REDIS_URL" .')
assert_eq "grep -rnw (word boundary)" "REDIS_URL" "$result"

result=$(extract 'grep -rn --color=never "authenticate!" app/controllers/')
assert_eq "grep -rn --color=never" "authenticate!" "$result"

result=$(extract 'grep -rn -e "pattern1" -e "pattern2" src/')
assert_not_empty "grep -rn with multiple -e patterns" "$result"

echo ""
echo "  ── grep -R (recursive, follow symlinks) ──"

result=$(extract 'grep -R "WebSocket" lib/')
assert_eq "grep -R" "WebSocket" "$result"

result=$(extract 'grep -Rn "config.cache" .')
assert_eq "grep -Rn" "config.cache" "$result"

result=$(extract 'grep -Rni "secret_key" .')
assert_eq "grep -Rni" "secret_key" "$result"

echo ""
echo "  ── rg (ripgrep — always recursive) ──"

result=$(extract 'rg "ActionCable" app/')
assert_eq "rg double-quoted" "ActionCable" "$result"

result=$(extract "rg 'order_status' app/")
assert_eq "rg single-quoted" "order_status" "$result"

result=$(extract 'rg ActionCable app/')
assert_eq "rg unquoted" "ActionCable" "$result"

result=$(extract 'rg "WebSocket" --type ruby')
assert_eq "rg with trailing --type" "WebSocket" "$result"

result=$(extract 'rg -i "fixme" .')
assert_eq "rg -i case insensitive" "fixme" "$result"

result=$(extract 'rg -l "TODO" src/')
assert_eq "rg -l list files" "TODO" "$result"

result=$(extract 'rg -w "User" app/models/')
assert_eq "rg -w word boundary" "User" "$result"

result=$(extract 'rg --hidden "API_KEY" .')
assert_eq "rg --hidden" "API_KEY" "$result"

result=$(extract 'rg -g "*.ts" "interface Props" src/')
assert_eq "rg -g glob filter" "interface Props" "$result"

result=$(extract 'rg -t py "import" src/')
assert_eq "rg -t filetype" "import" "$result"

result=$(extract 'rg --pcre2 "(?<=class\s)\w+" app/')
assert_not_empty "rg --pcre2 lookahead" "$result"

result=$(extract 'rg -c "TODO" .')
assert_eq "rg -c count" "TODO" "$result"

result=$(extract 'rg -F "std::vector<int>" src/')
assert_eq "rg -F fixed string with angle brackets" "std::vector<int>" "$result"

result=$(extract 'rg --json "pattern" src/')
assert_eq "rg --json output" "pattern" "$result"

result=$(extract 'rg -U "fn\n\s+main" src/')
assert_not_empty "rg -U multiline" "$result"

result=$(extract 'rg "def (create|update|destroy)" app/controllers/')
assert_not_empty "rg alternation in pattern" "$result"

echo ""
echo "  ── ag (the silver searcher — always recursive) ──"

result=$(extract "ag 'render_template' app/views/")
assert_eq "ag single-quoted" "render_template" "$result"

result=$(extract 'ag "ActionMailer" app/')
assert_eq "ag double-quoted" "ActionMailer" "$result"

result=$(extract 'ag -l "TODO" .')
assert_eq "ag -l list files" "TODO" "$result"

result=$(extract 'ag -w "User" app/')
assert_eq "ag -w word boundary" "User" "$result"

result=$(extract 'ag --hidden "SECRET" .')
assert_eq "ag --hidden" "SECRET" "$result"

echo ""
echo "  ── ack (always recursive) ──"

result=$(extract 'ack "def initialize" app/')
assert_eq "ack double-quoted" "def initialize" "$result"

result=$(extract "ack 'validates' app/models/")
assert_eq "ack single-quoted" "validates" "$result"

result=$(extract 'ack --type=ruby "module" lib/')
assert_eq "ack --type= with pattern" "module" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 2: Commands that should NOT be intercepted
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── non-search commands (must produce empty output) ──"

result=$(extract 'ls -la')
assert_empty "ls" "$result"

result=$(extract 'cat README.md')
assert_empty "cat" "$result"

result=$(extract 'echo "hello world"')
assert_empty "echo" "$result"

result=$(extract 'mkdir -p src/components')
assert_empty "mkdir" "$result"

result=$(extract 'cd /tmp && pwd')
assert_empty "cd && pwd" "$result"

result=$(extract 'npm install express')
assert_empty "npm install" "$result"

result=$(extract 'git log --oneline')
assert_empty "git log" "$result"

result=$(extract 'python3 manage.py migrate')
assert_empty "python3 manage.py" "$result"

result=$(extract 'docker ps -a')
assert_empty "docker" "$result"

result=$(extract 'curl -s https://example.com')
assert_empty "curl" "$result"

echo ""
echo "  ── non-recursive grep (should NOT match) ──"

result=$(extract 'grep "pattern" file.txt')
assert_empty "plain grep on single file" "$result"

result=$(extract 'grep -n "error" log.txt')
assert_empty "grep -n on single file" "$result"

result=$(extract 'grep -c "TODO" file.py')
assert_empty "grep -c on single file" "$result"

result=$(extract 'grep -l "import" file1.py file2.py')
assert_empty "grep -l on explicit file list" "$result"

result=$(extract 'echo "some text" | grep "pattern"')
assert_empty "piped grep (not a codebase search)" "$result"

result=$(extract 'cat file.txt | grep -i "error"')
assert_empty "cat piped to grep" "$result"

result=$(extract 'ps aux | grep python')
assert_empty "ps aux | grep (process search)" "$result"

result=$(extract 'env | grep PATH')
assert_empty "env | grep (env search)" "$result"

result=$(extract 'git log | grep "fix"')
assert_empty "git log | grep" "$result"

result=$(extract 'history | grep "deploy"')
assert_empty "history | grep" "$result"

echo ""
echo "  ── egrep / fgrep non-recursive (should NOT match) ──"

result=$(extract 'egrep "TODO|FIXME" file.txt')
assert_empty "egrep on single file" "$result"

result=$(extract 'fgrep "literal string" file.txt')
assert_empty "fgrep on single file" "$result"

result=$(extract 'egrep -r "TODO|FIXME" .')
assert_not_empty "egrep -r (recursive) should match" "$result"

result=$(extract 'fgrep -r "literal" src/')
assert_not_empty "fgrep -r (recursive) should match" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 3: Pattern preservation — terms must survive extraction intact
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── simple identifiers ──"

result=$(extract 'grep -rn "ActionCable" app/')
assert_eq "PascalCase identifier" "ActionCable" "$result"

result=$(extract 'grep -rn "snake_case_name" app/')
assert_eq "snake_case identifier" "snake_case_name" "$result"

result=$(extract 'grep -rn "camelCaseName" app/')
assert_eq "camelCase identifier" "camelCaseName" "$result"

result=$(extract 'grep -rn "SCREAMING_SNAKE" app/')
assert_eq "SCREAMING_SNAKE constant" "SCREAMING_SNAKE" "$result"

result=$(extract 'grep -rn "kebab-case-name" app/')
assert_eq "kebab-case identifier" "kebab-case-name" "$result"

result=$(extract 'grep -rn "Class::Method" app/')
assert_eq "Ruby/C++ scope operator" "Class::Method" "$result"

result=$(extract 'grep -rn "package.module" app/')
assert_eq "dotted identifier" "package.module" "$result"

result=$(extract 'grep -rn "org.example.MyClass" app/')
assert_eq "Java fully qualified name" "org.example.MyClass" "$result"

result=$(extract 'grep -rn "@decorator" app/')
assert_eq "decorator / annotation" "@decorator" "$result"

result=$(extract 'grep -rn "$variable" app/')
assert_eq "shell/PHP variable" '$variable' "$result"

echo ""
echo "  ── multi-word / phrase patterns ──"

result=$(extract 'grep -rn "import flask" src/')
assert_eq "two-word phrase" "import flask" "$result"

result=$(extract 'grep -rn "class UserController" app/')
assert_eq "class declaration" "class UserController" "$result"

result=$(extract 'grep -rn "def self.find_by" app/')
assert_eq "method definition with dot" "def self.find_by" "$result"

result=$(extract 'grep -rn "has_many :orders" app/models/')
assert_eq "Rails association with colon" "has_many :orders" "$result"

echo ""
echo "  ── special characters in search terms ──"

result=$(extract 'grep -rn "TODO:" app/')
assert_eq "trailing colon" "TODO:" "$result"

result=$(extract "grep -rn \"config['key']\" app/")
assert_not_empty "bracket access" "$result"

result=$(extract 'grep -rn "fn()" app/')
assert_not_empty "function call parens" "$result"

result=$(extract 'grep -rn "user->name" app/')
assert_eq "arrow operator" "user->name" "$result"

result=$(extract 'grep -rn "arr[0]" app/')
assert_not_empty "array subscript" "$result"

result=$(extract 'grep -rn "#include" app/')
assert_eq "hash prefix" "#include" "$result"

result=$(extract 'grep -rn "//nolint" app/')
assert_eq "double slash prefix" "//nolint" "$result"

result=$(extract 'rg -F "a]b" src/')
assert_eq "literal bracket in -F pattern" "a]b" "$result"

echo ""
echo "  ── patterns that current parser mangles (regex stripping) ──"

result=$(extract 'grep -rn "process_order" app/')
assert_eq "underscore preserved" "process_order" "$result"

result=$(extract 'grep -rn "config.redis" app/')
assert_eq "dot in identifier preserved" "config.redis" "$result"

result=$(extract 'grep -rn "user.email" app/')
assert_eq "dot as literal (common in identifiers)" "user.email" "$result"

result=$(extract 'grep -rn "price > 0" app/')
assert_not_empty "comparison operator preserved" "$result"

result=$(extract 'rg -F "std::cout << x" src/')
assert_eq "C++ stream operator (-F fixed)" "std::cout << x" "$result"

result=$(extract 'rg -F "a+b" src/')
assert_eq "plus in -F fixed string" "a+b" "$result"

result=$(extract 'rg -F "foo|bar" src/')
assert_eq "pipe in -F fixed string" "foo|bar" "$result"

result=$(extract 'rg -F "file.txt" src/')
assert_eq "dot in -F filename" "file.txt" "$result"

echo ""
echo "  ── regex patterns where stripping is acceptable ──"

result=$(extract 'grep -rn "^def process" app/')
assert_contains "anchor-prefixed: keeps 'process'" "process" "$result"
assert_contains "anchor-prefixed: keeps 'def'" "def" "$result"

result=$(extract 'grep -rn "TODO.*FIXME" app/')
assert_contains "wildcard: keeps TODO" "TODO" "$result"

result=$(extract 'rg "(create|update|destroy)" app/')
assert_not_empty "alternation produces something useful" "$result"

result=$(extract 'grep -rn "user\." app/')
assert_contains "escaped dot: keeps user" "user" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 4: find command variants
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── find -name ──"

result=$(extract 'find . -name "*.rb"')
assert_eq "find -name glob extension" ".rb" "$result"

result=$(extract 'find . -name "Dockerfile"')
assert_eq "find -name exact" "Dockerfile" "$result"

result=$(extract 'find . -name "*.test.ts"')
assert_eq "find -name double extension" ".test.ts" "$result"

result=$(extract 'find . -name "config.*"')
assert_eq "find -name stem with wildcard ext" "config." "$result"

result=$(extract "find . -name '*.py'")
assert_eq "find -name single-quoted" ".py" "$result"

result=$(extract 'find src -name "*.tsx" -o -name "*.ts"')
assert_not_empty "find -name with -o (or)" "$result"

echo ""
echo "  ── find -iname ──"

result=$(extract 'find . -iname "readme*"')
assert_eq "find -iname" "readme" "$result"

result=$(extract 'find . -iname "*.JSON"')
assert_eq "find -iname case insensitive" ".JSON" "$result"

echo ""
echo "  ── find with other predicates ──"

result=$(extract 'find . -wholename "*/.claude/*"')
assert_not_empty "find -wholename" "$result"

result=$(extract 'find . -path "*/migrations/*"')
assert_not_empty "find -path" "$result"

result=$(extract 'find . -type f -name "*.log" -mtime -7')
assert_eq "find with -type and -mtime" ".log" "$result"

result=$(extract 'find . -name "*.pyc" -delete')
assert_eq "find -name with -delete" ".pyc" "$result"

echo ""
echo "  ── fd (always recursive) ──"

result=$(extract 'fd "controller"')
assert_eq "fd positional pattern" "controller" "$result"

result=$(extract 'fd controller')
assert_eq "fd unquoted pattern" "controller" "$result"

result=$(extract 'fd -e py "test"')
assert_eq "fd -e extension filter" "test" "$result"

result=$(extract 'fd -t f "config"')
assert_eq "fd -t type filter" "config" "$result"

result=$(extract 'fd --hidden "env"')
assert_eq "fd --hidden" "env" "$result"

result=$(extract 'fd -g "*.ts" src/')
assert_not_empty "fd -g glob" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 5: Edge cases and tricky commands
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── edge cases ──"

result=$(extract 'grep -rn "" app/')
assert_empty "empty pattern" "$result"

result=$(extract 'rg "" src/')
assert_empty "rg empty pattern" "$result"

result=$(extract 'grep -rn "a" app/')
assert_eq "single character pattern" "a" "$result"

result=$(extract 'grep -rn "AB" app/')
assert_eq "two character pattern" "AB" "$result"

result=$(extract 'rg "café" src/')
assert_eq "unicode pattern" "café" "$result"

result=$(extract 'rg "naïve" src/')
assert_eq "unicode diacritics" "naïve" "$result"

result=$(extract 'grep -rn "日本語" src/')
assert_eq "CJK characters" "日本語" "$result"

result=$(extract 'ast-grep -p "console.log($$$)" src/')
assert_empty "ast-grep should not be intercepted" "$result"

echo ""
echo "  ── flag-eating: flags with arguments must not leak into pattern ──"

result=$(extract 'grep -rn -m 5 "pattern" app/')
assert_eq "grep -m N doesn't eat pattern" "pattern" "$result"

result=$(extract 'grep -rn --max-count=5 "pattern" app/')
assert_eq "grep --max-count= doesn't eat pattern" "pattern" "$result"

result=$(extract 'rg -m 5 "pattern" src/')
assert_eq "rg -m N doesn't eat pattern" "pattern" "$result"

result=$(extract 'rg -A 3 -B 3 "pattern" src/')
assert_eq "rg -A N -B N context flags" "pattern" "$result"

result=$(extract 'rg --max-columns 200 "pattern" src/')
assert_eq "rg --max-columns N" "pattern" "$result"

result=$(extract 'grep -rn -f patterns.txt app/')
assert_empty "grep -f file (pattern from file, not inline)" "$result"

echo ""
echo "  ── compound / chained commands ──"

result=$(extract 'grep -rn "TODO" app/ | wc -l')
assert_eq "grep piped to wc" "TODO" "$result"

result=$(extract 'grep -rn "FIXME" app/ | sort | uniq')
assert_eq "grep piped to sort/uniq" "FIXME" "$result"

result=$(extract 'rg "error" src/ && echo "found"')
assert_eq "rg chained with &&" "error" "$result"

result=$(extract 'rg "warn" src/ || true')
assert_eq "rg chained with ||" "warn" "$result"

report
