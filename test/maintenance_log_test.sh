#!/usr/bin/env bash
# Tests for maintenance-log.sh
#
# maintenance-log.sh fires when the maintain sub-skill is invoked. It creates
# the timestamped log file that maintenance actions are recorded into. If it
# doesn't create the file, maintenance actions have nowhere to be logged.
# If it doesn't output the path, the sub-skill doesn't know where to write.
# If the path doesn't include the session ID, you can't trace a log back
# to the session that produced it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
SKILL_SCRIPT="$SCRIPT_DIR/../.claude/skills/knowledge/maintenance-log.sh"
FIXTURES="$SCRIPT_DIR/fixtures"

echo "── maintenance-log.sh ──"

export PROJECT_ROOT="$FIXTURES/project"
export CLAUDE_SESSION_ID="test-session-mlog"
unset REPO_ROOT 2>/dev/null || true

# The maintain sub-skill captures this script's stdout to know where the
# log file lives. If nothing is printed, the sub-skill has no log path
# and can't record what happened during maintenance.
log_path=$("$SKILL_SCRIPT")
assert_not_empty "outputs the log file path" "$log_path"

# The script needs to actually create the file, not just print a path.
# If the file doesn't exist, the first append during maintenance fails.
assert_file_exists "log file exists on disk" "$log_path"

# The session ID in the filename is how you trace a maintenance log back
# to the session that ran it. Without it, logs from different sessions
# are indistinguishable.
assert_contains "path includes session ID" "test-session-mlog" "$log_path"

# Maintenance logs live under the maintenance/ subdirectory. If they end
# up somewhere else, the directory structure contract is broken and cleanup
# or archival tools won't find them.
assert_contains "path is under maintenance/" "/maintenance/" "$log_path"

# The path should include a date-based directory for organization.
# Without it, hundreds of log files pile up in a single flat directory.
date_dir=$(date '+%Y%m%d')
assert_contains "path includes date directory" "$date_dir" "$log_path"

# Clean up the created log and its directory
rm -f "$log_path"
rmdir "$(dirname "$log_path")" 2>/dev/null || true

report
