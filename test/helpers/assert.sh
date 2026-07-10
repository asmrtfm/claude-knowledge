#!/usr/bin/env bash
# Shared assertion functions for test files.
# Source this at the top of each test.

PASS=0
FAIL=0
ERRORS=""

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ((PASS++)) || true
    echo "  ✓ $label"
    echo "    actual: $actual"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    expected: $expected\n    actual:   $actual"
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    ((PASS++)) || true
    echo "  ✓ $label"
    echo "    needle: $needle"
    echo "    actual: $haystack"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    expected to contain: $needle\n    actual: $haystack"
    echo "  ✗ $label"
    echo "    needle: $needle"
    echo "    actual: $haystack"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    ((PASS++)) || true
    echo "  ✓ $label"
    echo "    absent: $needle"
    echo "    actual: $haystack"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    expected NOT to contain: $needle\n    actual: $haystack"
    echo "  ✗ $label"
    echo "    should not contain: $needle"
    echo "    actual: $haystack"
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [[ -z "$actual" ]]; then
    ((PASS++)) || true
    echo "  ✓ $label"
    echo "    actual: (empty)"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    expected empty but got: $actual"
    echo "  ✗ $label"
    echo "    actual: $actual"
  fi
}

assert_not_empty() {
  local label="$1" actual="$2"
  if [[ -n "$actual" ]]; then
    ((PASS++)) || true
    echo "  ✓ $label"
    echo "    actual: $actual"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    expected non-empty but got empty"
    echo "  ✗ $label"
    echo "    actual: (empty)"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    ((PASS++)) || true
    echo "  ✓ $label"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    file not found: $path"
    echo "  ✗ $label"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    ((PASS++)) || true
    echo "  ✓ $label"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    file should not exist: $path"
    echo "  ✗ $label"
  fi
}

assert_line_count() {
  local label="$1" expected="$2" file="$3"
  local actual
  actual=$(wc -l < "$file" | tr -d ' ')
  if [[ "$expected" == "$actual" ]]; then
    ((PASS++)) || true
    echo "  ✓ $label"
  else
    ((FAIL++)) || true
    ERRORS="$ERRORS\n  FAIL: $label\n    expected $expected lines, got $actual"
    echo "  ✗ $label"
  fi
}

report() {
  echo ""
  echo "  $PASS passed, $FAIL failed"
  if [[ $FAIL -gt 0 ]]; then
    echo -e "$ERRORS"
    return 1
  fi
}
