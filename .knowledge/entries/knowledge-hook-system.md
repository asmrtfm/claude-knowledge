# Knowledge Hook System

> How the knowledge base and maintenance queue hooks work in this project.

tags: hooks knowledge search maintenance queue

## Architecture

The system has two hooks registered in `.claude/settings.json`:

1. **Knowledge Hook** (`PostToolUse` on `Bash`) — intercepts search commands
   (grep, find, rg, fd, etc.), extracts the search intent, and checks
   `.knowledge/entries/` for matching entries. Matches are appended to
   tool output so they appear alongside search results.

2. **Maintenance Queue** (`PostToolUse` on `Edit|Write|NotebookEdit`) — logs
   changed file paths to `.knowledge/.maintenance-queue.log`. Accumulates
   passively, never triggers action on its own.

## Key Files

- `.claude/hooks/knowledge-hook.sh` — main search interception hook
- `.claude/hooks/maintenance-queue.sh` — file change logger
- `.claude/hooks/lib/parse-search.sh` — extracts query terms from commands
- `.claude/hooks/lib/query-knowledge.sh` — searches entries for matches
- `.knowledge/index.md` — describes the knowledge base structure
- `.knowledge/entries/*.md` — individual curated entries

## Creating Entries

Entries are created collaboratively, not auto-generated. The right time
is when a session completes cleanly with headroom — not mid-task.
