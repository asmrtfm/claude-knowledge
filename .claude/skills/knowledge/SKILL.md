---
name: knowledge
description: Capture, query, and maintain project knowledge. Use to record architectural discoveries, gotchas, decisions, and domain concepts that are not obvious from reading the code.
argument-hint: capture | maintain | <search query>
---

## Overview

This skill manages a layered project knowledge system stored in `.claude/knowledge/` directories. Knowledge lives at two levels:

- **Org-level**: `$ORG_DIR/.claude/knowledge/` — cross-repo knowledge (entity naming, API contracts, how repos relate, platform conventions)
- **Project-level**: `$PROJECT_ROOT/.claude/knowledge/` (or `$REPO_ROOT`) — implementation-specific knowledge (model gotchas, controller patterns, service behavior)

Both levels share the same structure. When working in a project, both layers apply.

## Directory Structure

```
.claude/knowledge/
  INDEX.md                 # knowledge map: source_file -> [entry paths]
  MAINTENANCE_QUEUE        # auto-populated by hooks: files changed during sessions
  entries/
    architecture/          # how components connect and data flows
    decisions/             # why X was chosen over Y (ADR-lite)
    gotchas/               # non-obvious traps, footguns, things that break silently
    relationships/         # tight couplings, shared caches, co-dependent models
    workflows/             # deploy steps, release process, manual procedures
    domain/                # business concepts that differ from what code suggests
  historical/              # obsolete entries, same structure as entries/
  maintenance/             # archived maintenance logs (YYYYMMDD/HHMMSS_<session_id>.log)
```

## Routing

Parse $ARGUMENTS:
- If empty or `capture`: enter **Capture Mode** → read `skills/capture/SKILL.md`
- If `maintain`: enter **Maintain Mode** → read `skills/maintain/SKILL.md`
- Anything else: treat as a search query → enter **Query Mode** → read `skills/query/SKILL.md`

$ARGUMENTS
