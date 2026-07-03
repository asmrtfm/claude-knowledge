---
name: capture
---

## Capture Mode

Record new knowledge entries based on the current session's discoveries.

1. Ask: "What did you discover?" (or use context from the current session if the discovery is obvious).
2. Determine the appropriate **category** from the directory list in the parent skill.
   New categories are allowed but treated as a high bar — only create one when no
   existing category reasonably fits and the concept is clearly distinct.
3. Determine the appropriate **layer**:
   - If the knowledge applies across repos (naming conventions, API contracts, cross-repo relationships): org-level (`$ORG_DIR/.claude/knowledge/`)
   - If it's specific to this project's implementation: project-level (`$PROJECT_ROOT/.claude/knowledge/` or `$REPO_ROOT/.claude/knowledge/`)
4. Identify all **source files** the knowledge relates to (files where you'd need this knowledge to work safely).
5. Write the entry:

```markdown
---
category: <category>
tags: <space-separated keywords for concept-based lookups>
files:
  - <relative/path/to/file>
  - <relative/path/to/other_file>
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
---

<Knowledge content. Be specific and actionable. Include:
- What is true (the fact or pattern)
- Why it matters (what breaks or goes wrong without this knowledge)
- How to apply it (concrete guidance when working in these files)>
```

6. Save to `entries/<category>/<kebab-case-name>.md`
7. Update `INDEX.md` — add or update lines for each file referenced in the entry's `files:` field.

### INDEX.md Format

```
# Knowledge Map
# source_file -> knowledge entries that reference it

app/models/order.rb -> [architecture/order-lifecycle.md, gotchas/order-cache.md]
app/controllers/concerns/persistable.rb -> [architecture/category-filtering.md]
```

One line per source file. Entries listed in brackets, comma-separated. Keep lines sorted alphabetically by source file path.
