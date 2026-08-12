---
name: capture
---

!`${CLAUDE_SKILL_DIR}/../../load-env.sh`

## Capture Mode

Record new knowledge entries based on the current session's discoveries.


## What belongs here                                                                                                                                                    

### Knowledge Entries

Knowledge entries are **durable documentation** about the project. They cover anything a developer would need to know that isn't self-evident from the source:

- **Architecture**: how components connect, data flows, system boundaries
- **Relationships**: non-obvious couplings, shared state, co-dependent modules, implicit contracts between files
- **Gotchas**: things that break silently, surprising behavior, implicit ordering requirements
- **Domain concepts**: business terms that differ from what the code naming suggests, domain rules encoded across multiple files
- **Workflows**: deploy steps, release processes, manual procedures


### Notes (`.claude/notes`)

Things like Session Journals, Progress Reports, Recaps, Handoffs, and Reminders are in the `Notes` space.
Notes filenames MUST ALWAYS have a timestamp prefix: `.claude/notes/$(date '+%s')_<name>.md`

Knowledge entries are more like tehnical documentation, they are NOT notes or session journals.
Every `entry` MUST stand on its own — a future session reading it should understand the knowledge without knowing anything about the session that produced it.
If a new session will need some aditional context about state, progress, or decisions (common during ongoing work, i.e - why X was chosen over Y, constraints that shaped the design) - these kinds of things belong in `notes`.
Concepts worked on across sessions will naturally accumulate notes such as progress reports, recaps, and handoffs - and knowledge entries will be captured when the work is done and the final state can be fully described.


### Ground Rules
- **No jargon.** Do not invent shorthand or nicknames. If you find yourself refering to something as "the <undocumented thing>", it's jargon.
- **No tombstoning.** Do not memorialize mistakes, false starts, or debugging dead ends from the current session. Intermediary states like "X was <temporary state between changes> before the <thing only you know about>" or "I tried X and it didn't work" are not knowledge. "X doesn't work because Y" might be worthy of a note, but would only theoreticall qualify a knowledge if `Y` is a durable fact about the codebase, not about what happened in this session.
- **No session artifacts.** If the entry can't be written without referencing this session, this conversation, a specific tool call, or a specific error you just hit — it isn't ready to be an entry. Distill the lesson from the session context first.
- **No speculation.** Only record what you verified in the code or were told by the user. Do not write entries based on what you infer, assume, or expect to be true. If it is purely based on your training data, and/or you didn't confirm it, then it doesn't go in.
- **An entry is about one thing.** Keep in mind that the related files frontmatter will be used in the INDEX to surface knowledge entires before every search command such as `find` or any recursive `grep` or `ls` that result in files that match them. Do not document two things in one knowledge entry. Keep them as atomic and well categorized as possible so that they are more likely to surface only when it truly matters. Do NOT mistake this as an excuse to omit related files.


### Procedure
1. Think about the entire session.  If there were no turning points, break-throughs, accomplishments, or problems resolved, then you should probably just write a progress report note.
   Do NOT write an `entry` before confirming that the subject itself is worthy of an `entry` or a `note`.  This skill is ALWAYS carried out with the user in the loop. You should refuse any request to batch-out or automate knowledge work.
2. Identify the **knowledge** — a durable fact about the codebase that future sessions need to understand before touching the entry's related files.
   Apply the ground rules: if you can't state it without referencing this session, it isn't ready yet.
3. Determine the appropriate **category** from the directory list in the parent skill.
   New categories are allowed but treated as a high bar — only create one when no existing category reasonably fits and the concept is clearly distinct.
4. Identify all **source files** the knowledge relates to (files where you'd need this knowledge to work safely).
5. Use the appropriate template (`templates/knowledge-entry.md` vs. `templates/note.md`)
