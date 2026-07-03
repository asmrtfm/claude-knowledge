# Roadmap

> Ideas, planned features, and architectural changes — discussed first, implemented when ready.

## Active

- **Knowledge System Rebuild** — Rebuild the knowledge hook system incorporating
  architectural features from prior prototypes (night-district org-level, malsi-app).
  _(2026-07-02)_

  ### 1. FILE_INDEX.md (reverse map)

  The primary lookup mechanism is a reverse map: `source_file -> [entry paths]`.
  Each line maps a source code file path (e.g. `app/models/order.rb`) to the list
  of knowledge entries relevant to that file (e.g. `[architecture/order-lifecycle.md,
  gotchas/order-cache.md]`). When the search interception hook fires, it checks this
  index for matches rather than brute-forcing a token search across all entry files.
  The current implementation greps every entry for tokenized search terms — that works
  with a handful of entries but gets noisy and slow as the knowledge base grows. The
  index gives O(1) lookup by file path and keeps entry matching precise.

  The index is also greppable from the other direction: because entry paths encode the
  category in the directory structure (e.g. `gotchas/order-cache.md`), you can grep
  the right side for concept keywords or category names and land on both the relevant
  knowledge entries and the codebase files they relate to. One file, two lookup vectors.

  ### 2. Layered knowledge (org-level + repo/project-level)

  Two knowledge directories, both checked during lookups: org-level for cross-repo
  knowledge (naming conventions, API contracts, how repos relate to each other) and
  repo/project-level for implementation-specific details (model gotchas, controller
  patterns, caching behavior). The improvement over prior prototypes: discovery is
  driven by env vars in `settings.json` (`ORG_NAME`, `ORG_DIR`, `REPO_NAME`,
  `REPO_ROOT`, or `PROJECT_NAME`, `PROJECT_ROOT` when not a git repo), not by git
  or directory conventions. The hooks handle the resolution logic, so the system works
  in any project regardless of git or org structure.

  ### 3. Categorized entries

  Entries live in subdirectories: `architecture/`, `decisions/`, `gotchas/`,
  `relationships/`, `workflows/`, `domain/`. These are defaults, not a closed set —
  new categories are allowed but treated as a high bar. The capture and maintain
  sub-skills will include guidance that forming new categories must be done sparingly.

  ### 4. Entry frontmatter

  Each entry has structured YAML frontmatter: `category` (mirrors the subdirectory),
  `tags` (searchable keywords for concept-based lookups), `files` (the source files
  the knowledge relates to — this is what drives the FILE_INDEX.md reverse map),
  `created` and `updated` dates for staleness signals during maintenance.

  ### 5. Three modes as sub-skills

  `capture`, `maintain`, `query` as separate skill files so each mode's instructions
  only load into context when invoked. The parent skill handles argument-based routing —
  parsing the argument to determine the mode and delegating to the right sub-skill.

  ### 6. Historical archive

  Obsolete entries move to `historical/` (same subdirectory structure as `entries/`)
  instead of being deleted. Normal greps against `entries/` don't hit stale content,
  but the history is preserved if you need to trace why something was once believed.
  Like all actions in maintenance mode, archiving is collaborative — the model presents
  what it found and what it thinks should happen, then waits for the user to confirm
  or adjust before carrying out the action.

  ### 7. Maintenance log archival

  Each maintenance run gets timestamped session logs at
  `maintenance/YYYYMMDD/HHMMSS_<session_id>.log`. These logs archive what happened
  during a `/knowledge maintain` run — which entries were reviewed, what was updated
  or archived, what was confirmed still valid. This is distinct from the maintenance
  queue, which passively logs file changes during normal work sessions.

  The modification from prior prototypes: log creation is not the model's job. The
  maintain sub-skill auto-fires a script on invocation that sets up the log file and
  environment (like the malsi prototype's `!${CLAUDE_SKILL_DIR}/maintainence_log.sh`).
  The model doesn't create or manage the log scaffolding — the script handles it.
  Eventually, actual hooks will check for indicators that a maintenance session is
  active and respond accordingly.

  ### 8. MAINTENANCE_QUEUE format

  Richer format than the current simple log:
  `<tool_use_id> <YYYYMMDD_HHMMSS mtime> <session_id> <filepath>`. A PostToolUse
  hook (part of normal session operation, not maintenance mode) scrubs entries whose
  files didn't actually change — if the mtime is unchanged after the tool call, the
  entry is removed from the queue. This catches no-op edits and blocked permissions
  so they don't pollute the queue with false positives.

  ### 9. Tool name as signal in MAINTENANCE_QUEUE

  The hook that writes to MAINTENANCE_QUEUE already knows the tool name from the
  hook input — `Edit` (file existed and was modified), `Write` (new file created),
  `NotebookEdit`, etc. This distinction carries forward into maintenance mode: the
  maintain sub-skill can differentiate between "this existing file was modified, check
  if its knowledge entries are still accurate" vs "this is a new file, determine if it
  warrants a knowledge entry at all." This replaces the prior prototype's pre-edit
  FILE_INDEX.md check — the tool name in the queue entry provides the same signal
  without any mid-task interruption or context loading.

## Considering

_Ideas we've talked through but haven't committed to yet._

## Completed

_Shipped and done._

- **Knowledge Hook System** — Passive search interception and maintenance queue hooks
  for reducing redundant exploration across sessions. No auto-memory, no interruption,
  no auto-generated entries. Knowledge entries are curated collaboratively when sessions
  have headroom. _(2026-07-02)_
