# claude-knowledge

A knowledge system for Claude Code. Installed into target projects via `init.sh`, which copies hooks, skills, and directory scaffolding into the project's `.claude/`.

## `knowledge` (CLI)

Top-level commands: `init`, `hooks`, `link`, `unlink`, `show`, `sort`, `purge`, `rekey`.
Subcommands: `index list [-f json|yaml]`, `entries list [pattern] [-f fields]`.
Run `knowledge --help` or `knowledge <command> --help` for details.

## `init.sh`

Interactive installer. Detects mode (`repo`, `org`, `project`) from the target directory. Copies hooks and skills, creates the `.claude/knowledge/` directory structure (entries/, historical/, maintenance/, inspections/), merges hook configs into settings.json, generates `.envrc`, and runs `verify-settings.sh` at the end. Handles frontmatter migration for entries from older installs via `yq`.

Puts `bin/` on PATH during install for `safe_copy`, `prompt_value`, and `nearest`. Installs `nearest` to `~/bin` or `~/.local/bin` if not already available.

## `verify-settings.sh`

Validates that settings.json, settings.local.json, and .envrc all agree on env vars (REPO_NAME, REPO_ROOT, ORG_DIR, etc.) and that every hook script has a matching entry in the chosen settings file. Sourced by `init.sh` post-install, or runnable standalone against a target directory.

## hooks/knowledge/

Hooks that get copied into target projects. All check `.disabled_hooks` and exit early if disabled.

- `pre-search.sh` — PreToolUse on Bash. Intercepts grep/find/rg commands: runs the command, captures output, looks up result file paths in INDEX.md, and surfaces matching knowledge entries via `additionalContext`. Also injects `--exclude-dir` / `-not -path` for directories listed in `.ignored`. Replaces the original command with `cat <cached output>` so results aren't fetched twice.
- `pre-edit.sh` — PreToolUse on Edit/Write/NotebookEdit. Records file mtime before edit to `mtime.log`, keyed by tool_use_id.
- `maintenance-queue.sh` — PostToolUse on Edit/Write/etc, also PostToolUseFailure and PermissionDenied. Compares post-edit mtime against `mtime.log` to detect actual changes; appends changed file paths to MAINTENANCE_QUEUE with format `<tool_use_id> <mtime> <session_id> <tool_name> <filepath>`. Skips files inside `.claude/`.
- `post-read.sh` — PostToolUse on Read. Logs knowledge entry paths read this session to `<session_cache>/reads.log` so `pre-search.sh` can skip re-surfacing them.
- `post-write.sh` — PostToolUse on Write. Tracks which sessions created knowledge entries by logging to `knowledge/write-logs/<session_id>.list`.
- `lib/resolve-env.sh` — Resolves REPO_ROOT, ORG_DIR, PROJECT_ROOT from filesystem and settings.json. Shared by hooks and skills.
- `.ignored` — Directories to exclude from search interception (default: `.claude`).

## skills/knowledge/

The `/knowledge` skill. Routes on argument: `capture`, `maintain`, `inspect`. `load-env.sh` bootstraps env vars (sources `resolve-env.sh`).

- `skills/capture/` — Record new knowledge entries. `templates/knowledge-entry.md` has the frontmatter schema and procedure. `templates/note.md` for session notes.
- `skills/maintain/` — Review entries flagged in MAINTENANCE_QUEUE or do a broader staleness scan. `maintenance-log.sh` auto-creates a timestamped log file on invocation. `audit.sh` scans entries' `files:` frontmatter and INDEX.md for source paths that no longer exist, queuing findings to MAINTENANCE_QUEUE.
- `skills/inspect/` — Structured validity review: scans entries via `knowledge entries list`, classifies by inspection status, evaluates one at a time against six criteria (validity, testability, coverage, tombstones, jargon, recommendations). Writes inspection log, stamps frontmatter.

## bin/

- `nearest` — Walk up from a starting directory (`--from`) to find a file or directory matching a name and test flag (e.g. `-d .claude`, `-f .envrc`). Used by hooks and init.
- `safe_copy` — Copy with interactive diff and overwrite prompt when destination differs.
- `prompt_value` — Prompt for a value with a default. Used during `init.sh`.
- `merge_hooks` — Merge hooks and permissions into a settings file. Superseded by inline logic in `init.sh` but still exists as a standalone script.
