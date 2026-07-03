# Knowledge Hook System

A passive knowledge retrieval and maintenance tracking system for Claude Code sessions.

## What It Does

Two hooks sit on the Claude Code execution layer:

1. **Knowledge Hook** — When the agent runs a search command (grep, find, rg, fd, ag, ack),
   this hook extracts the search terms, checks the knowledge base for relevant entries, and
   appends matches to the tool output. The agent sees prior knowledge exactly where it's
   already looking, with zero interruption.

2. **Maintenance Queue** — When files are created or edited (via Edit, Write, or NotebookEdit),
   this hook logs the file path and timestamp to `.maintenance-queue.log`. The queue builds
   passively and is reviewed collaboratively when the session has headroom.

## What It Doesn't Do

- Interrupt the agent mid-task
- Auto-generate knowledge entries
- Inject system reminders or nag prompts
- Fire on non-search commands
- Act on the maintenance queue automatically

## Directory Structure

```
.knowledge/
├── README.md                  # This file
├── index.md                   # Entry format spec and structure docs
├── entries/                   # Curated knowledge entries (*.md)
│   └── knowledge-hook-system.md
└── .maintenance-queue.log     # Passively accumulated file change log

.claude/
├── settings.json              # Hook registration config
└── hooks/
    ├── knowledge-hook.sh      # Search interception hook (PostToolUse → Bash)
    ├── maintenance-queue.sh   # File change logger (PostToolUse → Edit|Write|NotebookEdit)
    └── lib/
        ├── parse-search.sh    # Extracts query terms from search commands
        └── query-knowledge.sh # Scores and returns matching knowledge entries
```

## How Search Interception Works

```
Agent runs: grep -rn "ActionCable" app/
                │
                ▼
    knowledge-hook.sh (PostToolUse)
                │
                ├── Detects "grep" in command
                ├── parse-search.sh extracts "ActionCable"
                ├── query-knowledge.sh searches entries/*.md
                │   ├── Tokenizes search terms
                │   ├── Scores each entry by token overlap
                │   └── Returns title, summary, tags, filename
                │
                ▼
    Matching entries appended to grep output
    ━━━ Knowledge Base Matches ━━━
    • **ActionCable Channels** [1/1 tokens matched]
      How real-time channels are structured in this app.
      → actioncable-channels.md
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The agent sees the knowledge entries alongside the search results it was already reading.
No context switch, no meta-work, no interruption.

## Writing Knowledge Entries

Entries live in `.knowledge/entries/` as markdown files. Format:

```markdown
# Title

> One-line summary for display in search matches.

tags: space separated tokens for matching

Body — context, patterns, conventions, gotchas, or anything
that saves a future session from re-deriving it.
```

### When to Create Entries

- After a task completes cleanly with context window headroom
- When the maintenance queue has accumulated changes worth documenting
- Collaboratively — the human decides what's worth keeping

### When NOT to Create Entries

- Mid-task under cognitive load
- For one-off situational corrections
- Automatically or speculatively

## Maintenance Queue

The `.maintenance-queue.log` file is a simple append-only log:

```
2026-07-02T21:34:43Z | Edit | /home/me/app/models/user.rb
2026-07-02T21:35:01Z | Write | /home/me/app/services/checkout.rb
```

Each file path appears only once per queue cycle (deduped on append).
Processed lines are cleared after collaborative review.
