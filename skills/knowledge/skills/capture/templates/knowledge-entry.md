
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


### Procedure

- **Self-review against ground rules.** Read the draft back. Does it reference this session, a mistake you made, or a debugging path you took? If so, it belongs in notes. The entry should read like documentation, not a postmortem.
- Save to `entries/<category>/<kebab-case-name>.md`
- Update `INDEX.md` — for each file in the entry's `files:` field, run: `knowledge link <source_file> <category/entry-name.md>`
  This creates or appends to the source file's mapping and keeps the index sorted.

### INDEX.md Management

Use the `knowledge` CLI to manage INDEX.md rather than editing it by hand:

```bash
knowledge link <source> <entry>           # link a source file to an entry
knowledge unlink <source> <entry>         # unlink
knowledge purge <entry>                   # remove entry from all sources
knowledge rekey <old_path> <new_path>     # update after a file move
knowledge list [-f json|yaml]             # view the index
knowledge index sort                      # sort index alphabetically
```


### Org-Level Knowledge (skip if `$ORG_DIR` is not set)

If the knowledge applies across repos — naming conventions, API contracts, cross-repo relationships, shared platform conventions — store it at the org level (`$ORG_DIR/.claude/knowledge/`) instead of the project level.

Use the same entry format and procedure. The only difference is the storage path: save to `$ORG_DIR/.claude/knowledge/entries/<category>/<name>.md` and update `$ORG_DIR/.claude/knowledge/INDEX.md`.
