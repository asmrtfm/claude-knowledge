# Memory Migration — Implementation Notes

## Goal

Add an installer step that offers to:
1. Back up existing auto-memory entries
2. Fold them into the knowledge system as entries
3. Run the inspector on them to surface tombstones and jargon

The inspector will almost certainly find both in abundance, which proves
what auto-memory actually produces.

## Where memories live

```
~/.claude/projects/<mangled-path>/memory/
```

The mangled path is the project directory with leading `/` dropped and all `/`
replaced by `-`. Example:

```
/home/me/Desktop/workspace/malsi-app -> -home-me-Desktop-workspace-malsi-app
```

Each memory dir contains:
- `MEMORY.md` — an index file with a table of all entries (feedback + project)
- Individual `.md` files — one per memory entry

## Memory file format

```yaml
---
name: feedback-no-invented-jargon
description: "Don't invent shorthand terms..."
metadata:
  node_type: memory
  type: feedback           # or "project"
  originSessionId: <uuid>
---

<body text>
```

Two types observed: `feedback` (behavioral corrections) and `project` (project-specific facts).

## What the migration step should do

1. Derive the mangled path from `$TARGET` and check if the memory dir exists
2. Count entries (exclude MEMORY.md)
3. Ask the user if they want to migrate
4. If yes:
   - Back up the entire memory dir somewhere under `.claude/knowledge/`
   - Convert entries into knowledge system format (rewrite frontmatter to use
     category/tags/files/created/updated/inspected fields)
   - Stage them for inspection (the `migrated` category or similar)
   - Tell the user to run `/knowledge inspect` on them

## What the inspector will find

The `feedback_no_invented_jargon.md` memory is a perfect example of what
auto-memory produces but fails to enforce. That memory existed and Claude
still filled plans with jargon. The entry itself is well-written — the
system just doesn't work.

Most feedback-type memories are tombstones by nature: they describe a
correction that happened in a specific session. "Don't do X" entries are
session artifacts unless X is a durable constraint of the codebase.

Many will contain jargon — session-specific shorthand that future sessions
have to guess at.

## Frontmatter conversion

Auto-memory format -> Knowledge entry format:

```yaml
# From:
name: feedback-no-invented-jargon
description: "..."
metadata:
  node_type: memory
  type: feedback
  originSessionId: <uuid>

# To:
category: migrated
tags:
  - <derived from name/description>
files: []
created: <derive from file mtime or leave blank>
updated: <same>
inspected:  # left blank — inspector will pick these up first
```

## Auto-memory disable setting

The correct settings.json key for disabling auto-memory needs to be verified.
The jq command to apply it once confirmed:

```bash
jq '.<correct.key> = false' "$SETTINGS" > "$SETTINGS.tmp" \
  && mv "$SETTINGS.tmp" "$SETTINGS"
```






---





 154 -# ── Offer to disable built-in auto memory ──                                                                                                                           
 155 -                                                                                                                                                                        
 154  echo ""
 157 -echo "  Auto-memory is interventionist. It watches for corrections, rejections, and"                                                                                    
 158 -echo "  task completions, then interrupts the workflow to generate and persist a"                                                                                       
 159 -echo "  memory entry. The act of capturing competes with the actual work, introduces"                                                                                   
 160 -echo "  its own failure modes, and pollutes future sessions with low-signal entries."                                                                                   
 161 -echo "  Memories are a dumping ground on a conveyor belt — good and bad all get"                                                                                        
 162 -echo "  deleted based on age, in the background, with no user input."                                                                                                   
 163 -echo ""                                                                                                                                                                 
 164 -echo "  See docs/on-auto-memory.md for details."                                                                                                                        
 165 -echo ""                                                                                                                                                                 
 166 -read -rp "  Disable auto memory for this project? [Y/n]: " disable_memory                                                                                               
 167 -if [[ "$disable_memory" != [nN]* ]]; then                                                                                                                               
 168 -  jq '.settings.memory = false' "$SETTINGS" > "$SETTINGS.tmp" \                                                                                                         
 169 -    && mv "$SETTINGS.tmp" "$SETTINGS"                                                                                                                                   
 170 -  echo "  auto memory disabled"                                                                                                                                         
 171 -else                                                                                                                                                                    
 172 -  echo "  auto memory left enabled"                                                                                                                                     
 173 -fi                                                                                                                                                                      
 174 -                                                                                                                                                                        
 175 -echo ""  
