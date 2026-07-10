---
name: inspect
---

!`${CLAUDE_SKILL_DIR}/../../load-env.sh`

## Inspect Mode

Review knowledge entries for validity and assess whether they point to behavior
that should have test coverage. Produces an inspection log with actionable
recommendations.

### Selection

1. Scan all entries under `entries/` and extract frontmatter using `yq`:
   ```bash
   for f in $(find entries/ -name '*.md' -type f); do
     category=$(echo "$f" | cut -d/ -f2)
     inspected=$(yq --front-matter=extract '.inspected' "$f" 2>/dev/null)
     updated=$(yq --front-matter=extract '.updated' "$f" 2>/dev/null)
     echo "$category|$inspected|$updated|$f"
   done
   ```
2. Classify each entry:
   - **uninspected**: `inspected` is null/missing
   - **stale-entry**: `inspected` is literally `stale`
   - **needs-reinspection**: `updated > inspected` (date comparison)
   - **current**: `inspected >= updated` — skip these
3. Group results by category. Present a single-select category menu showing counts:
   ```
   gotchas (3 uninspected, 1 stale)
   architecture (2 uninspected)
   decisions (1 needs-reinspection)
   ```
   Categories with zero actionable entries are omitted.
4. After category selection, present a multi-select entry menu within that category.
   Label each entry with its status.

### Inspection

Launch a subagent (Agent tool) for the selected entries. The subagent prompt must include:
- The full path to each selected entry
- Instruction to read each entry and all files in its `files:` frontmatter field
- The inspection criteria below
- A 90K context budget note: keep source file reads targeted — read only what's needed to verify the entry and assess test coverage

#### Inspection Criteria

For each entry, the subagent evaluates:

1. **Validity**: Do the referenced files still exist? Does the entry's content match
   what the code actually does? If not, the entry is stale.
2. **Testability**: Does the entry describe behavior, a constraint, or a failure mode
   in code? If so, it's testable. Decisions, workflows, naming conventions, and
   rationale entries are not testable — mark them as inspected and move on.
3. **Coverage**: For testable entries, check whether tests already exist that cover
   the described behavior. Look in the project's test directories for relevant test
   files matching the source files.
4. **Tombstones**: Does the entry memorialize a problem that was introduced and
   resolved within the same session? Does it reference behavior that no longer
   exists, framed as "X used to do Y but now does Z"? Does it describe a fix
   for something that isn't broken in the current code? These are tombstones —
   artifacts of a session's debugging history, not durable knowledge. Flag every
   instance found.
5. **Jargon**: Did you have to guess or infer what a term, name, or shorthand
   means? If so, it's jargon. This includes nicknames for components, unexplained
   abbreviations, session-specific shorthands that a future reader wouldn't
   recognize, or domain terms used without definition. The test is simple: did
   reading it require any leap or assumption about meaning? If yes, flag it and
   quote the specific term.
6. **Recommendations**: For testable entries with missing coverage, describe what
   tests should be written — specific enough to act on, referencing the entry's
   knowledge as the specification.

#### Subagent Output

The subagent writes an inspection log to:
```
.claude/knowledge/inspections/<YYYYMMDD>_<HHMMSS>.md
```

Format:
```markdown
# Inspection Log — <YYYY-MM-DD HH:MM:SS>

## <relative/path/to/entry.md>
- **Status**: valid | stale
- **Testable**: yes | no
- **Coverage**: covered | partial | missing | n/a
- **Tombstones**: none | <quoted text and why it's a tombstone>
- **Jargon**: none | <quoted term and what you had to guess it meant>
- **Recommendation**: <actionable next step, or "none">

## <next entry...>
```

### Post-Inspection

After the subagent returns, the orchestrator stamps each inspected entry's frontmatter:
- Valid entries: set `inspected: <YYYY-MM-DD>`
- Stale entries: set `inspected: stale`

Use `yq` to update the frontmatter in place:
```bash
yq --front-matter=process '.inspected = "<value>"' -i "$entry_path"
```

Entries marked stale are also appended to `MAINTENANCE_QUEUE` so maintenance mode
picks them up, using the format:
```
inspect <YYYYMMDD_HHMMSS> <session_id> Inspect <entry_path>
```
