---
name: knowledge
description: Capture, query, and maintain project knowledge. Use to record architectural discoveries, gotchas, and domain concepts that are not obvious from reading the code.
argument-hint: capture | maintain | inspect | <search query>
---

!`${CLAUDE_SKILL_DIR}/load-env.sh`


## Overview

This skill manages a project knowledge system stored in `.claude/knowledge/`. Knowledge lives at the project level (`$PROJECT_ROOT/.claude/knowledge/` or `$REPO_ROOT/.claude/knowledge/`).

If `$ORG_DIR` is set, an org-level layer is also checked at `$ORG_DIR/.claude/knowledge/` — useful for cross-repo knowledge such as entity naming, API contracts, and platform conventions. Both layers share the same structure.


## Directory Structure

```
.claude/knowledge/
├── INDEX.md               # knowledge map: source_file -> [entry paths, ...]
├── MAINTENANCE_QUEUE      # auto-populated by hooks: files changed during sessions
├── entries/
│   ├── architecture/          # how components connect and data flows
│   ├── domain/                # business concepts that differ from what code suggests
│   ├── gotchas/               # non-obvious traps, footguns, things that break silently
│   ├── relationships/         # tight couplings, shared caches, co-dependent models
│   └── workflows/             # deploy steps, release process, manual procedures
│
├── historical/            # obsolete entries, same structure as entries/
├── maintenance/           # archived maintenance logs (YYYYMMDD/HHMMSS_<session_id>.log)
└── inspections/           # inspection logs (YYYYMMDD_HHMMSS.md)
```

### INDEX.md

Maps source files to the knowledge entries that are relevant to them.

**Format**: `relative/path/to/source_file -> [<category>/<entry-name>.md, ...]`

> Left side: Source file path, relative to project root.
> Right side: Array of knowledge entry paths, relative to .claude/knowledge.


## Routing

Parse $ARGUMENTS:
- If empty or `capture`: enter **Capture Mode** → read `skills/capture/SKILL.md`
- If `maintain`: enter **Maintain Mode** → read `skills/maintain/SKILL.md`
- If `inspect`: enter **Inspect Mode** → read `skills/inspect/SKILL.md`
- Anything else: treat as a search query → enter **Query Mode** → read `skills/query/SKILL.md`

$ARGUMENTS
