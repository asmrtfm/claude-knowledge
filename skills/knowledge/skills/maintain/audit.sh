#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────────
# audit.sh — Pre-maintenance file-existence audit for knowledge entries.
#
# Scans every knowledge entry's YAML frontmatter for its `files:` list,
# then checks whether each referenced source file exists on disk.
# Also checks INDEX.md for source file paths that no longer exist.
#
# Findings are appended to MAINTENANCE_QUEUE using the standard format:
#
#   <tool_use_id> <YYYYMMDD_HHMMSS mtime> <session_id> <tool_name> <filepath>
#
# For audit-generated entries:
#   - tool_use_id is "audit_<timestamp>"
#   - mtime is the current timestamp (time of audit)
#   - session_id is inherited from the environment or "audit"
#   - tool_name is "Audit" (distinguishes from hook-generated Edit/Write entries)
#   - filepath is the missing source file path
#
# Intended to run automatically at the start of `/knowledge maintain`
# so that stale-reference issues are already queued when the interactive
# review begins.
#
# Exit codes:
#   0 — no missing files found
#   1 — one or more missing files appended to queue
# ─────────────────────────────────────────────────────────────────────

# ─── Help ───────────────────────────────────────────────────────────
_usage() { ${MANPAGER:-${PAGER:-cat}} <<'HELPTEXT'
NAME
        audit.sh — Pre-maintenance file-existence audit for knowledge entries

DESCRIPTION
        Scans all knowledge entries and INDEX.md for references to source
        files that no longer exist on disk. Appends findings to
        MAINTENANCE_QUEUE so they are surfaced during the maintain session.

        Run automatically at the start of `/knowledge maintain`.

OPTIONS
    --help, -h, help    Show this help text.

QUEUE FORMAT
        Audit entries use tool_name "Audit" to distinguish them from
        hook-generated entries (Edit/Write). The filepath field contains
        the missing source file path. The entry that references it can
        be looked up via INDEX.md or by grepping entries' frontmatter.

HELPTEXT

  exit ${1:-0}
}

[[ "${1,,}" != +(\-)@(h)?(elp) ]] || _usage


# ─── Setup ──────────────────────────────────────────────────────────

KNOWLEDGE_DIR="${REPO_ROOT:-$PROJECT_ROOT}/.claude/knowledge"
ENTRIES_DIR="$KNOWLEDGE_DIR/entries"
INDEX="$KNOWLEDGE_DIR/INDEX.md"
QUEUE="$KNOWLEDGE_DIR/MAINTENANCE_QUEUE"

# Timestamp and session for queue entries
STAMP="$(date '+%Y%m%d_%H%M%S')"
AUDIT_ID="audit_${STAMP}"
SESSION="${CLAUDE_SESSION_ID:-${SESSION_ID:-audit}}"

# Track how many issues we find
issues=0


# ─── Audit entries ──────────────────────────────────────────────────
# For each .md file under entries/, extract the `files:` block from
# YAML frontmatter and check that every listed path exists relative
# to the repo root.

while IFS= read -r entry_path; do
  # Parse YAML frontmatter to extract files: list
  in_frontmatter=false
  in_files=false

  while IFS= read -r line; do
    # Detect frontmatter boundaries (delimited by --- lines)
    if [[ "$line" == "---" ]]; then
      if [ "$in_frontmatter" = true ]; then
        break  # End of frontmatter
      else
        in_frontmatter=true
        continue
      fi
    fi

    if [ "$in_frontmatter" = true ]; then
      # Detect the start of the files: block
      if [[ "$line" == "files:" ]]; then
        in_files=true
        continue
      fi

      if [ "$in_files" = true ]; then
        # Lines in the files block match "  - <path>"
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
          file_ref="${BASH_REMATCH[1]}"
          # Check if the source file exists relative to repo root
          if [ ! -f "${REPO_ROOT:-$PROJECT_ROOT}/$file_ref" ]; then
            echo "${AUDIT_ID} ${STAMP} ${SESSION} Audit ${file_ref}" >> "$QUEUE"
            ((issues++))
          fi
        else
          # Non-list line means we've left the files: block
          in_files=false
        fi
      fi
    fi
  done < "$entry_path"
done < <(find "$ENTRIES_DIR" -name '*.md' | sort)


# ─── Audit INDEX.md ────────────────────────────────────────────────
# Check every source file path in INDEX.md (left side of " -> ")
# to verify it still exists on disk. Catches orphaned lines whose
# entry may have been archived but the index line left behind.

while IFS= read -r line; do
  # Skip header comments and blank lines
  [[ "$line" =~ ^# ]] && continue
  [[ -z "$line" ]] && continue

  # Extract the source file path (everything before " -> ")
  src="$(echo "$line" | cut -d' ' -f1)"
  if [ ! -f "${REPO_ROOT:-$PROJECT_ROOT}/$src" ]; then
    echo "${AUDIT_ID} ${STAMP} ${SESSION} Audit ${src}" >> "$QUEUE"
    ((issues++))
  fi
done < "$INDEX"


# ─── Output ────────────────────────────────────────────────────────

if [ "$issues" -eq 0 ]; then
  echo "audit: no missing files"
else
  echo "audit: queued $issues missing file(s)"
fi

exit $(( issues > 0 ? 1 : 0 ))
