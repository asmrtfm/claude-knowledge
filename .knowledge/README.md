# Knowledge Hook System

A passive knowledge retrieval and maintenance tracking system for Claude Code sessions.

## What It Does

Two hooks sit on the Claude Code execution layer:

1. **Pre-Search Hook** (`PreToolUse` on `Bash`) — When the agent is about to run a search
   command (grep, find, rg), this hook runs the command early to get a file list. If the
   command produced results, each file path is looked up in INDEX.md for mapped knowledge
   entries. If the command produced zero results (no codebase matches at all), the fallback
   re-runs the exact same command — same pattern, same flags — with the target path swapped
   to each knowledge base's `entries/` directory. Any matches from either path are passed
   via `additionalContext`. The original command always runs unmodified.

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
├── hooks/
│   └── knowledge/
│       ├── pre-search.sh      # Search interception (PreToolUse → Bash)
│       ├── pre-edit.sh        # Pre-edit hook (PreToolUse → Edit|Write|NotebookEdit)
│       ├── maintenance-queue.sh # File change logger (PostToolUse → Edit|Write|NotebookEdit)
│       └── lib/
│           ├── resolve-env.sh     # Resolves knowledge dirs from env/filesystem
│           └── query-knowledge.sh # Scores and returns matching knowledge entries
└── skills/
    └── knowledge/
        └── skills/
            └── maintain/
                ├── audit.sh       # Pre-maintenance file-existence audit
                └── maintenance-log.sh # Maintenance session logging
```

## How Search Interception Works

```
Agent runs: grep -rn "ActionCable" app/
                │
                ▼
    pre-search.sh (PreToolUse)
                │
                ├── Detects recursive grep
                ├── Runs command early with -l to get file paths
                │
                ├── If files found:
                │   └── Look up each path in INDEX.md → mapped entries
                │
                ├── If zero files found:
                │   └── Re-run same command with target path swapped
                │       to each knowledge base's entries/ directory
                │
                ▼
    Matches (from either path) passed via additionalContext
    Original command runs unmodified
```

The agent sees knowledge entries alongside the search results it was already reading.
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
