#!/usr/bin/env bash
# Tests for parse-search.sh
#
# parse-search.sh extracts search terms from codebase-search commands so the
# knowledge hook can grep its INDEX for relevant entries. The extracted terms
# must be usable as grep patterns against plain-text filenames and notes.
#
# Design constraints (from knowledge.sh, the conceptual source of truth):
#   - Only intercept recursive/codebase searches, not one-off greps
#   - Preserve the search term faithfully — don't mangle it
#   - Produce empty output for non-search commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
PARSE="$SCRIPT_DIR/../.claude/hooks/lib/parse-search.sh"

echo "── parse-search.sh ──"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 1: Commands that SHOULD be intercepted (recursive/codebase search)
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── grep -r (recursive grep) ──"

result=$(echo 'grep -r "ActionCable" app/' | "$PARSE")
assert_eq "grep -r double-quoted" "ActionCable" "$result"

result=$(echo "grep -r 'order_status' app/" | "$PARSE")
assert_eq "grep -r single-quoted" "order_status" "$result"

result=$(echo 'grep -rn "ActionCable" app/' | "$PARSE")
assert_eq "grep -rn" "ActionCable" "$result"

result=$(echo 'grep -rni "ActionCable" app/' | "$PARSE")
assert_eq "grep -rni" "ActionCable" "$result"

result=$(echo 'grep -rl "TODO" src/' | "$PARSE")
assert_eq "grep -rl (list files)" "TODO" "$result"

result=$(echo 'grep -rn --include="*.py" "import flask" src/' | "$PARSE")
assert_eq "grep -rn --include with pattern" "import flask" "$result"

result=$(echo 'grep -rn --exclude-dir=node_modules "useState" .' | "$PARSE")
assert_eq "grep -rn --exclude-dir" "useState" "$result"

result=$(echo 'grep -rn -C3 "def process" app/' | "$PARSE")
assert_eq "grep -rn with context flag" "def process" "$result"

result=$(echo 'grep -rn -A5 -B2 "class User" app/models/' | "$PARSE")
assert_eq "grep -rn with before/after context" "class User" "$result"

result=$(echo 'grep -rnw "REDIS_URL" .' | "$PARSE")
assert_eq "grep -rnw (word boundary)" "REDIS_URL" "$result"

result=$(echo 'grep -rn --color=never "authenticate!" app/controllers/' | "$PARSE")
assert_eq "grep -rn --color=never" "authenticate!" "$result"

result=$(echo 'grep -rn -e "pattern1" -e "pattern2" src/' | "$PARSE")
assert_not_empty "grep -rn with multiple -e patterns" "$result"

echo ""
echo "  ── grep -R (recursive, follow symlinks) ──"

result=$(echo 'grep -R "WebSocket" lib/' | "$PARSE")
assert_eq "grep -R" "WebSocket" "$result"

result=$(echo 'grep -Rn "config.cache" .' | "$PARSE")
assert_eq "grep -Rn" "config.cache" "$result"

result=$(echo 'grep -Rni "secret_key" .' | "$PARSE")
assert_eq "grep -Rni" "secret_key" "$result"

echo ""
echo "  ── rg (ripgrep — always recursive) ──"

result=$(echo 'rg "ActionCable" app/' | "$PARSE")
assert_eq "rg double-quoted" "ActionCable" "$result"

result=$(echo "rg 'order_status' app/" | "$PARSE")
assert_eq "rg single-quoted" "order_status" "$result"

result=$(echo 'rg ActionCable app/' | "$PARSE")
assert_eq "rg unquoted" "ActionCable" "$result"

result=$(echo 'rg "WebSocket" --type ruby' | "$PARSE")
assert_eq "rg with trailing --type" "WebSocket" "$result"

result=$(echo 'rg -i "fixme" .' | "$PARSE")
assert_eq "rg -i case insensitive" "fixme" "$result"

result=$(echo 'rg -l "TODO" src/' | "$PARSE")
assert_eq "rg -l list files" "TODO" "$result"

result=$(echo 'rg -w "User" app/models/' | "$PARSE")
assert_eq "rg -w word boundary" "User" "$result"

result=$(echo 'rg --hidden "API_KEY" .' | "$PARSE")
assert_eq "rg --hidden" "API_KEY" "$result"

result=$(echo 'rg -g "*.ts" "interface Props" src/' | "$PARSE")
assert_eq "rg -g glob filter" "interface Props" "$result"

result=$(echo 'rg -t py "import" src/' | "$PARSE")
assert_eq "rg -t filetype" "import" "$result"

result=$(echo 'rg --pcre2 "(?<=class\s)\w+" app/' | "$PARSE")
assert_not_empty "rg --pcre2 lookahead" "$result"

result=$(echo 'rg -c "TODO" .' | "$PARSE")
assert_eq "rg -c count" "TODO" "$result"

result=$(echo 'rg -F "std::vector<int>" src/' | "$PARSE")
assert_eq "rg -F fixed string with angle brackets" "std::vector<int>" "$result"

result=$(echo 'rg --json "pattern" src/' | "$PARSE")
assert_eq "rg --json output" "pattern" "$result"

result=$(echo 'rg -U "fn\n\s+main" src/' | "$PARSE")
assert_not_empty "rg -U multiline" "$result"

result=$(echo 'rg "def (create|update|destroy)" app/controllers/' | "$PARSE")
assert_not_empty "rg alternation in pattern" "$result"

echo ""
echo "  ── ag (the silver searcher — always recursive) ──"

result=$(echo "ag 'render_template' app/views/" | "$PARSE")
assert_eq "ag single-quoted" "render_template" "$result"

result=$(echo 'ag "ActionMailer" app/' | "$PARSE")
assert_eq "ag double-quoted" "ActionMailer" "$result"

result=$(echo 'ag -l "TODO" .' | "$PARSE")
assert_eq "ag -l list files" "TODO" "$result"

result=$(echo 'ag -w "User" app/' | "$PARSE")
assert_eq "ag -w word boundary" "User" "$result"

result=$(echo 'ag --hidden "SECRET" .' | "$PARSE")
assert_eq "ag --hidden" "SECRET" "$result"

echo ""
echo "  ── ack (always recursive) ──"

result=$(echo 'ack "def initialize" app/' | "$PARSE")
assert_eq "ack double-quoted" "def initialize" "$result"

result=$(echo "ack 'validates' app/models/" | "$PARSE")
assert_eq "ack single-quoted" "validates" "$result"

result=$(echo 'ack --type=ruby "module" lib/' | "$PARSE")
assert_eq "ack --type= with pattern" "module" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 2: Commands that should NOT be intercepted
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── non-search commands (must produce empty output) ──"

result=$(echo 'ls -la' | "$PARSE")
assert_empty "ls" "$result"

result=$(echo 'cat README.md' | "$PARSE")
assert_empty "cat" "$result"

result=$(echo 'echo "hello world"' | "$PARSE")
assert_empty "echo" "$result"

result=$(echo 'mkdir -p src/components' | "$PARSE")
assert_empty "mkdir" "$result"

result=$(echo 'cd /tmp && pwd' | "$PARSE")
assert_empty "cd && pwd" "$result"

result=$(echo 'npm install express' | "$PARSE")
assert_empty "npm install" "$result"

result=$(echo 'git log --oneline' | "$PARSE")
assert_empty "git log" "$result"

result=$(echo 'python3 manage.py migrate' | "$PARSE")
assert_empty "python3 manage.py" "$result"

result=$(echo 'docker ps -a' | "$PARSE")
assert_empty "docker" "$result"

result=$(echo 'curl -s https://example.com' | "$PARSE")
assert_empty "curl" "$result"

echo ""
echo "  ── non-recursive grep (should NOT match) ──"

result=$(echo 'grep "pattern" file.txt' | "$PARSE")
assert_empty "plain grep on single file" "$result"

result=$(echo 'grep -n "error" log.txt' | "$PARSE")
assert_empty "grep -n on single file" "$result"

result=$(echo 'grep -c "TODO" file.py' | "$PARSE")
assert_empty "grep -c on single file" "$result"

result=$(echo 'grep -l "import" file1.py file2.py' | "$PARSE")
assert_empty "grep -l on explicit file list" "$result"

result=$(echo 'echo "some text" | grep "pattern"' | "$PARSE")
assert_empty "piped grep (not a codebase search)" "$result"

result=$(echo 'cat file.txt | grep -i "error"' | "$PARSE")
assert_empty "cat piped to grep" "$result"

result=$(echo 'ps aux | grep python' | "$PARSE")
assert_empty "ps aux | grep (process search)" "$result"

result=$(echo 'env | grep PATH' | "$PARSE")
assert_empty "env | grep (env search)" "$result"

result=$(echo 'git log | grep "fix"' | "$PARSE")
assert_empty "git log | grep" "$result"

result=$(echo 'history | grep "deploy"' | "$PARSE")
assert_empty "history | grep" "$result"

echo ""
echo "  ── egrep / fgrep non-recursive (should NOT match) ──"

result=$(echo 'egrep "TODO|FIXME" file.txt' | "$PARSE")
assert_empty "egrep on single file" "$result"

result=$(echo 'fgrep "literal string" file.txt' | "$PARSE")
assert_empty "fgrep on single file" "$result"

result=$(echo 'egrep -r "TODO|FIXME" .' | "$PARSE")
assert_not_empty "egrep -r (recursive) should match" "$result"

result=$(echo 'fgrep -r "literal" src/' | "$PARSE")
assert_not_empty "fgrep -r (recursive) should match" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 3: Pattern preservation — terms must survive extraction intact
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── simple identifiers ──"

result=$(echo 'grep -rn "ActionCable" app/' | "$PARSE")
assert_eq "PascalCase identifier" "ActionCable" "$result"

result=$(echo 'grep -rn "snake_case_name" app/' | "$PARSE")
assert_eq "snake_case identifier" "snake_case_name" "$result"

result=$(echo 'grep -rn "camelCaseName" app/' | "$PARSE")
assert_eq "camelCase identifier" "camelCaseName" "$result"

result=$(echo 'grep -rn "SCREAMING_SNAKE" app/' | "$PARSE")
assert_eq "SCREAMING_SNAKE constant" "SCREAMING_SNAKE" "$result"

result=$(echo 'grep -rn "kebab-case-name" app/' | "$PARSE")
assert_eq "kebab-case identifier" "kebab-case-name" "$result"

result=$(echo 'grep -rn "Class::Method" app/' | "$PARSE")
assert_eq "Ruby/C++ scope operator" "Class::Method" "$result"

result=$(echo 'grep -rn "package.module" app/' | "$PARSE")
assert_eq "dotted identifier" "package.module" "$result"

result=$(echo 'grep -rn "org.example.MyClass" app/' | "$PARSE")
assert_eq "Java fully qualified name" "org.example.MyClass" "$result"

result=$(echo 'grep -rn "@decorator" app/' | "$PARSE")
assert_eq "decorator / annotation" "@decorator" "$result"

result=$(echo 'grep -rn "$variable" app/' | "$PARSE")
assert_eq "shell/PHP variable" '$variable' "$result"

echo ""
echo "  ── multi-word / phrase patterns ──"

result=$(echo 'grep -rn "import flask" src/' | "$PARSE")
assert_eq "two-word phrase" "import flask" "$result"

result=$(echo 'grep -rn "class UserController" app/' | "$PARSE")
assert_eq "class declaration" "class UserController" "$result"

result=$(echo 'grep -rn "def self.find_by" app/' | "$PARSE")
assert_eq "method definition with dot" "def self.find_by" "$result"

result=$(echo 'grep -rn "has_many :orders" app/models/' | "$PARSE")
assert_eq "Rails association with colon" "has_many :orders" "$result"

echo ""
echo "  ── special characters in search terms ──"

result=$(echo 'grep -rn "TODO:" app/' | "$PARSE")
assert_eq "trailing colon" "TODO:" "$result"

result=$(echo 'grep -rn "config['\''key'\'']" app/' | "$PARSE")
assert_not_empty "bracket access" "$result"

result=$(echo 'grep -rn "fn()" app/' | "$PARSE")
assert_not_empty "function call parens" "$result"

result=$(echo 'grep -rn "user->name" app/' | "$PARSE")
assert_eq "arrow operator" "user->name" "$result"

result=$(echo 'grep -rn "arr[0]" app/' | "$PARSE")
assert_not_empty "array subscript" "$result"

result=$(echo 'grep -rn "#include" app/' | "$PARSE")
assert_eq "hash prefix" "#include" "$result"

result=$(echo 'grep -rn "//nolint" app/' | "$PARSE")
assert_eq "double slash prefix" "//nolint" "$result"

result=$(echo 'rg -F "a]b" src/' | "$PARSE")
assert_eq "literal bracket in -F pattern" "a]b" "$result"

echo ""
echo "  ── patterns that current parser mangles (regex stripping) ──"

# The current parser strips all regex metacharacters, turning meaningful
# search terms into nonsense. These tests document what the output SHOULD be.

result=$(echo 'grep -rn "process_order" app/' | "$PARSE")
assert_eq "underscore preserved" "process_order" "$result"

result=$(echo 'grep -rn "config.redis" app/' | "$PARSE")
assert_eq "dot in identifier preserved" "config.redis" "$result"

result=$(echo 'grep -rn "user.email" app/' | "$PARSE")
assert_eq "dot as literal (common in identifiers)" "user.email" "$result"

result=$(echo 'grep -rn "price > 0" app/' | "$PARSE")
assert_not_empty "comparison operator preserved" "$result"

result=$(echo 'rg -F "std::cout << x" src/' | "$PARSE")
assert_eq "C++ stream operator (-F fixed)" "std::cout << x" "$result"

result=$(echo 'rg -F "a+b" src/' | "$PARSE")
assert_eq "plus in -F fixed string" "a+b" "$result"

result=$(echo 'rg -F "foo|bar" src/' | "$PARSE")
assert_eq "pipe in -F fixed string" "foo|bar" "$result"

result=$(echo 'rg -F "file.txt" src/' | "$PARSE")
assert_eq "dot in -F filename" "file.txt" "$result"

echo ""
echo "  ── regex patterns where stripping is acceptable ──"

# When the pattern IS a regex (not -F), we need to extract something useful.
# But stripping should produce recognizable substrings, not garbage.

result=$(echo 'grep -rn "^def process" app/' | "$PARSE")
assert_contains "anchor-prefixed: keeps 'process'" "process" "$result"
assert_contains "anchor-prefixed: keeps 'def'" "def" "$result"

result=$(echo 'grep -rn "TODO.*FIXME" app/' | "$PARSE")
assert_contains "wildcard: keeps TODO" "TODO" "$result"
assert_contains "wildcard: keeps FIXME" "FIXME" "$result"

result=$(echo 'rg "(create|update|destroy)" app/' | "$PARSE")
assert_not_empty "alternation produces something useful" "$result"

result=$(echo 'grep -rn "user\." app/' | "$PARSE")
assert_contains "escaped dot: keeps user" "user" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 4: find command variants
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── find -name ──"

result=$(echo 'find . -name "*.rb"' | "$PARSE")
assert_eq "find -name glob extension" ".rb" "$result"

result=$(echo 'find . -name "Dockerfile"' | "$PARSE")
assert_eq "find -name exact" "Dockerfile" "$result"

result=$(echo 'find . -name "*.test.ts"' | "$PARSE")
assert_eq "find -name double extension" ".test.ts" "$result"

result=$(echo 'find . -name "config.*"' | "$PARSE")
assert_eq "find -name stem with wildcard ext" "config." "$result"

result=$(echo "find . -name '*.py'" | "$PARSE")
assert_eq "find -name single-quoted" ".py" "$result"

result=$(echo 'find src -name "*.tsx" -o -name "*.ts"' | "$PARSE")
assert_not_empty "find -name with -o (or)" "$result"

echo ""
echo "  ── find -iname ──"

result=$(echo 'find . -iname "readme*"' | "$PARSE")
assert_eq "find -iname" "readme" "$result"

result=$(echo 'find . -iname "*.JSON"' | "$PARSE")
assert_eq "find -iname case insensitive" ".JSON" "$result"

echo ""
echo "  ── find with other predicates ──"

result=$(echo 'find . -wholename "*/.claude/*"' | "$PARSE")
assert_not_empty "find -wholename" "$result"

result=$(echo 'find . -path "*/migrations/*"' | "$PARSE")
assert_not_empty "find -path" "$result"

result=$(echo 'find . -type f -name "*.log" -mtime -7' | "$PARSE")
assert_eq "find with -type and -mtime" ".log" "$result"

result=$(echo 'find . -name "*.pyc" -delete' | "$PARSE")
assert_eq "find -name with -delete" ".pyc" "$result"

echo ""
echo "  ── fd (always recursive) ──"

result=$(echo 'fd "controller"' | "$PARSE")
assert_eq "fd positional pattern" "controller" "$result"

result=$(echo 'fd controller' | "$PARSE")
assert_eq "fd unquoted pattern" "controller" "$result"

result=$(echo 'fd -e py "test"' | "$PARSE")
assert_eq "fd -e extension filter" "test" "$result"

result=$(echo 'fd -t f "config"' | "$PARSE")
assert_eq "fd -t type filter" "config" "$result"

result=$(echo 'fd --hidden "env"' | "$PARSE")
assert_eq "fd --hidden" "env" "$result"

result=$(echo 'fd -g "*.ts" src/' | "$PARSE")
assert_not_empty "fd -g glob" "$result"

# ════════════════════════════════════════════════════════════════════════════
# SECTION 5: Edge cases and tricky commands
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ── edge cases ──"

result=$(echo 'grep -rn "" app/' | "$PARSE")
assert_empty "empty pattern" "$result"

result=$(echo 'rg "" src/' | "$PARSE")
assert_empty "rg empty pattern" "$result"

result=$(echo 'grep -rn "a" app/' | "$PARSE")
assert_eq "single character pattern" "a" "$result"

result=$(echo 'grep -rn "AB" app/' | "$PARSE")
assert_eq "two character pattern" "AB" "$result"

result=$(echo 'rg "café" src/' | "$PARSE")
assert_eq "unicode pattern" "café" "$result"

result=$(echo 'rg "naïve" src/' | "$PARSE")
assert_eq "unicode diacritics" "naïve" "$result"

result=$(echo 'grep -rn "日本語" src/' | "$PARSE")
assert_eq "CJK characters" "日本語" "$result"

result=$(echo 'ast-grep -p "console.log($$$)" src/' | "$PARSE")
assert_empty "ast-grep should not be intercepted" "$result"

echo ""
echo "  ── flag-eating: flags with arguments must not leak into pattern ──"

result=$(echo 'grep -rn -m 5 "pattern" app/' | "$PARSE")
assert_eq "grep -m N doesn't eat pattern" "pattern" "$result"

result=$(echo 'grep -rn --max-count=5 "pattern" app/' | "$PARSE")
assert_eq "grep --max-count= doesn't eat pattern" "pattern" "$result"

result=$(echo 'rg -m 5 "pattern" src/' | "$PARSE")
assert_eq "rg -m N doesn't eat pattern" "pattern" "$result"

result=$(echo 'rg -A 3 -B 3 "pattern" src/' | "$PARSE")
assert_eq "rg -A N -B N context flags" "pattern" "$result"

result=$(echo 'rg --max-columns 200 "pattern" src/' | "$PARSE")
assert_eq "rg --max-columns N" "pattern" "$result"

result=$(echo 'grep -rn -f patterns.txt app/' | "$PARSE")
assert_empty "grep -f file (pattern from file, not inline)" "$result"

echo ""
echo "  ── compound / chained commands ──"

result=$(echo 'grep -rn "TODO" app/ | wc -l' | "$PARSE")
assert_eq "grep piped to wc" "TODO" "$result"

result=$(echo 'grep -rn "FIXME" app/ | sort | uniq' | "$PARSE")
assert_eq "grep piped to sort/uniq" "FIXME" "$result"

result=$(echo 'rg "error" src/ && echo "found"' | "$PARSE")
assert_eq "rg chained with &&" "error" "$result"

result=$(echo 'rg "warn" src/ || true' | "$PARSE")
assert_eq "rg chained with ||" "warn" "$result"

report
