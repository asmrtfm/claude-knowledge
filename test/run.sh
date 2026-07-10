#!/usr/bin/env bash
# Discovers and runs all *_test.sh files in this directory.
# Exit code is non-zero if any test file fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILURES=0

for test_file in "$SCRIPT_DIR"/*_test.sh; do
  [[ -f "$test_file" ]] || continue
  echo ""
  if ! bash "$test_file"; then
    ((FAILURES++))
  fi
done

echo ""
echo "══════════════════════════════════════"
if [[ $FAILURES -eq 0 ]]; then
  echo "All test files passed."
else
  echo "$FAILURES test file(s) had failures."
  exit 1
fi
