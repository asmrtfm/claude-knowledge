# Knowledge Hook System

> How the knowledge base and maintenance queue hooks work in this project.

tags: hooks knowledge search maintenance queue

## Architecture

The system has two hooks registered in `.claude/settings.json`:

1. **Pre-Search Hook** (`PreToolUse` on `Bash`) — intercepts search commands
   (grep, find, rg) and runs them early to get a file list. If the command
   produced results, each path is looked up in INDEX.md for mapped knowledge
   entries. If the command produced zero results, the fallback re-runs the
   exact same command with the target path swapped to each knowledge base's
   `entries/` directory. Matches from either path are passed via
   `additionalContext`. The original command always runs unmodified.

2. **Maintenance Queue** (`PostToolUse` on `Edit|Write|NotebookEdit`) — logs
   changed file paths to `.knowledge/.maintenance-queue.log`. Accumulates
   passively, never triggers action on its own.

## Key Files

- `.claude/hooks/knowledge/pre-search.sh` — search interception (PreToolUse → Bash)
- `.claude/hooks/knowledge/pre-edit.sh` — pre-edit hook (PreToolUse → Edit|Write|NotebookEdit)
- `.claude/hooks/knowledge/maintenance-queue.sh` — file change logger (PostToolUse)
- `.claude/hooks/knowledge/lib/resolve-env.sh` — resolves knowledge dirs from env/filesystem
- `.claude/hooks/knowledge/lib/query-knowledge.sh` — scores and returns matching entries
- `.knowledge/INDEX.md` — maps source file paths to knowledge entries
- `.knowledge/entries/*.md` — individual curated entries

## Creating Entries

Entries are created collaboratively, not auto-generated. The right time
is when a session completes cleanly with headroom — not mid-task.
