#!/usr/bin/env bash
# Tests for pre-edit.sh
#
# pre-edit.sh runs before every Edit/Write/NotebookEdit. Its only job is to
# snapshot the file's mtime so the post-edit hook can compare. If the snapshot
# is wrong or missing, the post-edit hook can't tell whether the file actually
# changed, and the maintenance queue either fills with false positives or
# misses real changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
HOOK="$SCRIPT_DIR/../.claude/hooks/pre-edit.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

echo "── pre-edit.sh ──"

# Clean up any leftover mtime files from previous runs
rm -f /tmp/knowledge-hooks/pre_edit_test_*.mtime
mkdir -p /tmp/knowledge-hooks

# The happy path: an existing file gets its mtime recorded. This is what
# happens on every Edit call. The post-edit hook reads this value back
# to decide if the file actually changed.
result=$(echo '{"tool_input":{"file_path":"'"$FIXTURES/project/.claude/knowledge/INDEX.md"'"},"tool_use_id":"pre_edit_test_1"}' \
  | "$HOOK")
assert_file_exists "records mtime for existing file" "/tmp/knowledge-hooks/pre_edit_test_1.mtime"
mtime_val=$(cat /tmp/knowledge-hooks/pre_edit_test_1.mtime)
assert_not_empty "mtime value is not empty" "$mtime_val"

# When Write creates a new file, it doesn't exist yet at PreToolUse time.
# The hook records "NEW" so the post-edit hook knows this was a creation,
# not a modification. Without this, the post-edit hook would compare against
# garbage and potentially skip logging the new file.
result=$(echo '{"tool_input":{"file_path":"/tmp/this_file_does_not_exist_xyz"},"tool_use_id":"pre_edit_test_2"}' \
  | "$HOOK")
mtime_val=$(cat /tmp/knowledge-hooks/pre_edit_test_2.mtime)
assert_eq "records NEW for file that doesn't exist yet" "NEW" "$mtime_val"

# If the hook input doesn't include a file_path (malformed tool call),
# the hook should do nothing. Creating an mtime file with no corresponding
# file path would leave orphaned temp files.
result=$(echo '{"tool_input":{},"tool_use_id":"pre_edit_test_3"}' \
  | "$HOOK")
assert_file_not_exists "no mtime file when file_path missing" "/tmp/knowledge-hooks/pre_edit_test_3.mtime"

# If there's no tool_use_id, the hook can't create a keyed temp file.
# The post-edit hook wouldn't be able to find the snapshot anyway, so
# writing anything would just be litter.
result=$(echo '{"tool_input":{"file_path":"'"$FIXTURES/project/.claude/knowledge/INDEX.md"'"}}' \
  | "$HOOK")
assert_file_not_exists "no mtime file when tool_use_id missing" "/tmp/knowledge-hooks/.mtime"

# Clean up
rm -f /tmp/knowledge-hooks/pre_edit_test_*.mtime

report
