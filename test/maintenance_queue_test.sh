#!/usr/bin/env bash
# Tests for maintenance-queue.sh
#
# maintenance-queue.sh runs after every Edit/Write/NotebookEdit. It decides
# whether the file actually changed (via mtime comparison with the pre-edit
# snapshot) and if so, writes a structured entry to MAINTENANCE_QUEUE. This
# queue is what the maintain sub-skill processes later. If entries are wrong,
# missing, or duplicated, maintenance mode either reviews the wrong files,
# misses real changes, or wastes time on duplicates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
HOOK="$SCRIPT_DIR/../.claude/hooks/maintenance-queue.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

echo "── maintenance-queue.sh ──"

# Each test needs a clean queue. We use the fixture queue and reset it between tests.
QUEUE="$FIXTURES/project/.claude/knowledge/MAINTENANCE_QUEUE"
export PROJECT_ROOT="$FIXTURES/project"
unset REPO_ROOT 2>/dev/null || true
mkdir -p /tmp/knowledge-hooks

# ── Basic entry creation ──

# The core job: a file was edited, write an entry. If this doesn't work,
# the maintenance queue is permanently empty and maintenance mode has
# nothing to process.
: > "$QUEUE"
echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/models/order.rb"'"},"tool_use_id":"mq_test_1","tool_name":"Edit"}' \
  | "$HOOK"
queue=$(cat "$QUEUE")
assert_contains "entry includes tool_use_id" "mq_test_1" "$queue"
assert_contains "entry includes file path" "app/models/order.rb" "$queue"
assert_contains "entry includes tool name" "Edit" "$queue"

# ── Tool name distinction ──

# The maintain sub-skill uses the tool name to decide how to process entries.
# Edit means "check existing knowledge for staleness." Write means "this is
# a new file, decide if it needs a knowledge entry." If Write shows up as
# Edit, new files get treated as modifications.
: > "$QUEUE"
echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/new_service.rb"'"},"tool_use_id":"mq_test_2","tool_name":"Write"}' \
  | "$HOOK"
queue=$(cat "$QUEUE")
assert_contains "Write tool name is preserved" "Write" "$queue"

# ── Deduplication ──

# If a file is edited ten times in a session, it should appear once in the
# queue. Without dedup, maintenance mode would process the same file ten
# times, wasting context and time.
: > "$QUEUE"
echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/models/order.rb"'"},"tool_use_id":"mq_test_3a","tool_name":"Edit"}' \
  | "$HOOK"
echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/models/order.rb"'"},"tool_use_id":"mq_test_3b","tool_name":"Edit"}' \
  | "$HOOK"
assert_line_count "same file appears only once" "1" "$QUEUE"

# Dedup must be path-specific. If editing order.rb suppresses a later entry
# for checkout_service.rb, real changes get silently lost.
echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/services/checkout_service.rb"'"},"tool_use_id":"mq_test_3c","tool_name":"Edit"}' \
  | "$HOOK"
assert_line_count "different file is not suppressed" "2" "$QUEUE"

# ── Mtime scrubbing: unchanged file ──

# When the pre-edit hook recorded the same mtime that the file has now,
# the file didn't actually change (no-op edit, blocked permission, etc.).
# Writing this to the queue would be a false positive — maintenance mode
# would review a file that nothing happened to.
: > "$QUEUE"
touch "$FIXTURES/project/app/unchanged.rb"
MTIME=$(stat -c %Y "$FIXTURES/project/app/unchanged.rb")
echo "$MTIME" > /tmp/knowledge-hooks/mq_test_4.mtime

echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/unchanged.rb"'"},"tool_use_id":"mq_test_4","tool_name":"Edit"}' \
  | "$HOOK"
queue=$(cat "$QUEUE")
assert_empty "no entry when mtime unchanged" "$queue"

# The mtime temp file should be cleaned up regardless of whether an entry
# was written. Leftover temp files accumulate and could collide with
# future tool_use_ids.
assert_file_not_exists "mtime temp file cleaned up" "/tmp/knowledge-hooks/mq_test_4.mtime"

# ── Mtime scrubbing: changed file ──

# When the pre-edit mtime differs from the current mtime, the file was
# genuinely modified. This is a real change that maintenance mode should
# review. If the scrubbing logic is too aggressive, real changes get dropped.
: > "$QUEUE"
touch "$FIXTURES/project/app/changed.rb"
echo "1000000000" > /tmp/knowledge-hooks/mq_test_5.mtime

echo '{"tool_input":{"file_path":"'"$FIXTURES/project/app/changed.rb"'"},"tool_use_id":"mq_test_5","tool_name":"Edit"}' \
  | "$HOOK"
queue=$(cat "$QUEUE")
assert_contains "entry written when mtime changed" "mq_test_5" "$queue"

# ── Missing input fields ──

# If the tool input has no file_path, there's nothing to log. The hook
# should exit silently, not crash or write a malformed entry.
: > "$QUEUE"
echo '{"tool_input":{},"tool_use_id":"mq_test_6","tool_name":"Edit"}' \
  | "$HOOK"
queue=$(cat "$QUEUE")
assert_empty "no entry when file_path missing" "$queue"

# Clean up test artifacts
rm -f "$FIXTURES/project/app/unchanged.rb" "$FIXTURES/project/app/changed.rb" "$FIXTURES/project/app/new_service.rb"
rm -f /tmp/knowledge-hooks/mq_test_*.mtime
: > "$QUEUE"

report
