---
name: capture
---

!`${CLAUDE_SKILL_DIR}/../../load-env.sh`

## Capture Mode

Record new knowledge entries based on the current session's discoveries.

### What belongs here                                                                                                                                                    
                                                                                                                                                                         
Knowledge entries are **durable documentation** about the project. They cover anything a developer would need to know that isn't self-evident from the source:

- **Architecture**: how components connect, data flows, system boundaries
- **Relationships**: non-obvious couplings, shared state, co-dependent modules, implicit contracts between files
- **Decisions**: why X was chosen over Y, constraints that shaped the design
- **Gotchas**: things that break silently, surprising behavior, implicit ordering requirements
- **Domain concepts**: business terms that differ from what the code naming suggests, domain rules encoded across multiple files
- **Workflows**: deploy steps, release processes, manual procedures

### Ground Rules

Knowledge entries are NOT session journals.
Every entry must stand on its own — a future session reading it should understand the knowledge without knowing anything about the session that produced it.

- **No tombstoning.** Do not memorialize mistakes, false starts, or debugging dead ends from the current session. "I tried X and it didn't work" is not knowledge. "X doesn't work because Y" might be, but only if Y is a durable fact about the codebase, not about what happened in this session.
- **No session artifacts.** If the entry can't be written without referencing this session, this conversation, a specific tool call, or a specific error you just hit — it isn't ready to be an entry. Distill the lesson from the session context first.
- **No speculation.** Only record what you verified in the code or were told by the user. Do not write entries based on what you infer, assume, or expect to be true. If you didn't confirm it, it doesn't go in.
- **Test: would this help someone who never saw this session?** If the answer is no, don't write it.

### Procedure

1. Identify the **knowledge** — a durable fact about the codebase that future sessions need.
   Apply the ground rules: if you can't state it without referencing this session, it isn't ready yet.
2. Determine the appropriate **category** from the directory list in the parent skill.
   New categories are allowed but treated as a high bar — only create one when no existing category reasonably fits and the concept is clearly distinct.
3. Identify all **source files** the knowledge relates to (files where you'd need this knowledge to work safely).
5. Write the entry:

```markdown
---
category: <category>
tags:
  - <keyword for concept-based lookups>
  - <additional keywords as needed>
files:
  - <relative/path/to/file>
  - <relative/path/to/other_file>
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
inspected: # date or "stale" — managed by inspect mode
---

<Be specific and actionable:
- What is true (the fact, constraint, or pattern)
- Why it matters (what breaks or goes wrong without this knowledge)
- How to work with it (concrete guidance when touching these files)>
```

6. **Self-review against ground rules.** Read the draft back. Does it reference this session, a mistake you made, or a debugging path you took? If so, rewrite until it doesn't. The entry should read like documentation, not a postmortem.
7. Save to `entries/<category>/<kebab-case-name>.md`
8. Update `INDEX.md` — add or update lines for each file referenced in the entry's `files:` field.

### INDEX.md Format

```
# Knowledge Map
# source_file -> knowledge entries that reference it

app/models/order.rb -> [architecture/order-lifecycle.md, gotchas/order-cache.md]
app/controllers/concerns/persistable.rb -> [architecture/category-filtering.md]
```

One line per source file. Entries listed in brackets, comma-separated. Keep lines sorted alphabetically by source file path.

### Org-Level Knowledge (skip if `$ORG_DIR` is not set)

If the knowledge applies across repos — naming conventions, API contracts, cross-repo relationships, shared platform conventions — store it at the org level (`$ORG_DIR/.claude/knowledge/`) instead of the project level.

Use the same entry format and procedure. The only difference is the storage path: save to `$ORG_DIR/.claude/knowledge/entries/<category>/<name>.md` and update `$ORG_DIR/.claude/knowledge/INDEX.md`.
