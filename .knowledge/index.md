# Knowledge Base Index

> Curated entries for reducing redundant exploration across sessions.
> Entries are created collaboratively — never auto-generated.

## Structure

- `entries/` — Individual knowledge entries as markdown files
- `.maintenance-queue.log` — Passively accumulated file change log for review

## Entry Format

Each entry in `entries/` follows this structure:

```markdown
# Title

> One-line summary of what this entry covers.

tags: space-separated tokens for search matching

Body content — context, patterns, gotchas, conventions, or
anything that would save a future session from re-deriving it.
```

## Maintenance Queue

The `.maintenance-queue.log` file accumulates file paths as they're
changed during sessions. It is not acted on automatically. When a
session has headroom, review the queue collaboratively to decide
which changes warrant new or updated knowledge entries, then clear
the processed lines.
