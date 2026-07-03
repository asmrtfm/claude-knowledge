---
name: maintain
---

!`${CLAUDE_SKILL_DIR}/../../maintenance-log.sh`

## Maintain Mode

Review and update knowledge entries that may be stale. The maintenance queue is
populated automatically by PostToolUse hooks that record file paths touched by
Edit, Write, and NotebookEdit tool calls during normal sessions.

### MAINTENANCE_QUEUE Format

```
<tool_use_id> <YYYYMMDD_HHMMSS mtime> <session_id> <tool_name> <filepath>
```

The `tool_name` field distinguishes between files that were modified (`Edit`) vs
newly created (`Write`) — use this to determine whether to check existing entries
for staleness or evaluate whether a new file warrants an entry.

A PostToolUse hook scrubs entries whose files didn't actually change (mtime unchanged).

### Procedure

1. Read `MAINTENANCE_QUEUE` in the project's `.claude/knowledge/` directory.
2. If the queue is empty, do a broader scan:
   a. Read all entries in the current layer
   b. For each, verify referenced files exist and knowledge still applies
   c. Flag any with missing files or obviously stale content
   d. Report what was confirmed or removed
   e. Stop here
3. For each queued filepath, grep `INDEX.md` for that path.
4. For files that have NO matching knowledge entries: read the actual source file
   and determine if a knowledge entry should be created. Present your recommendation
   to the user and wait for confirmation before creating anything.
5. For files that DO have matching knowledge entries, process **one entry at a time**:
   a. Read the knowledge entry
   b. Read the actual source file — **always read the real file, never rely on cached/prior content**
   c. Compare what the entry claims against what the file actually contains now
   d. Present your findings to the user:
      - If the entry is still accurate: confirm, no changes needed
      - If the entry is inaccurate or incomplete: propose the update, wait for confirmation
      - If the entry is entirely obsolete: propose moving it to `historical/` (same
        subdirectory structure as `entries/`), wait for confirmation. Remove from `INDEX.md`
        only after the user confirms
   e. Remove the processed line from `MAINTENANCE_QUEUE`
6. Like all actions in maintenance mode, every change is collaborative — present what
   you found and what you think should happen, then wait for the user to confirm or
   adjust before carrying out the action.

### New Categories

If during maintenance you encounter knowledge that doesn't fit any existing category,
you may propose a new one. This must be done sparingly — only when no existing category
reasonably fits and the concept is clearly distinct.
