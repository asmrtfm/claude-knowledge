#!/usr/bin/env bash

# ---------------------------------------------------------------------------------
# ### PostToolUse
#
# Runs immediately after a tool completes successfully.
#
# Matches on tool name, same values as PreToolUse.
#
# #### PostToolUse input
#
# `PostToolUse` hooks fire after a tool has already executed successfully. The input includes both `tool_input`, the arguments sent to the tool, and `tool_response`, the result it returned. The exact schema for both depends on the tool.
#
# ```json
# {
#   "session_id": "abc123",
#   "transcript_path": "/Users/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
#   "cwd": "/Users/...",
#   "permission_mode": "default",
#   "hook_event_name": "PostToolUse",
#   "tool_name": "Write",
#   "tool_input": {
#     "file_path": "/path/to/file.txt",
#     "content": "file content"
#   },
#   "tool_response": {
#     "filePath": "/path/to/file.txt",
#     "success": true
#   },
#   "tool_use_id": "toolu_01ABC123...",
#   "duration_ms": 12
# }
# ```
# | Field         | Description                                                                                                   |
# | :------------ | :------------------------------------------------------------------------------------------------------------ |
# | `duration_ms` | Optional. Tool execution time in milliseconds. Excludes time spent in permission prompts and PreToolUse hooks |
#
# #### PostToolUse decision control
#
# `PostToolUse` hooks can provide feedback to Claude after tool execution. In addition to the [JSON output fields](#json-output) available to all hooks, your hook script can return these event-specific fields:
#
# | Field                  | Description                                                                                                                        |
# | :--------------------- | :--------------------------------------------------------------------------------------------------------------------------------- |
# | `decision`             | `"block"` adds the `reason` next to the tool result. Claude still sees the original output; to replace it, use `updatedToolOutput` |
# | `reason`               | Explanation shown to Claude when `decision` is `"block"`                                                                           |
# | `additionalContext`    | String added to Claude's context alongside the tool result. See [Add context for Claude](#add-context-for-claude)                  |
# | `updatedToolOutput`    | Replaces the tool's output with the provided value before it is sent to Claude. The value must match the tool's output shape       |
# | `updatedMCPToolOutput` | Replaces the output for [MCP tools](#match-mcp-tools) only. Prefer `updatedToolOutput`, which works for all tools                  |
#
# The example below replaces the output of a `Bash` call. The replacement value matches the `Bash` tool's output shape:
#
# ```json
# {
#   "hookSpecificOutput": {
#     "hookEventName": "PostToolUse",
#     "additionalContext": "Additional information for Claude",
#     "updatedToolOutput": {
#       "stdout": "[redacted]",
#       "stderr": "",
#       "interrupted": false,
#       "isImage": false
#     }
#   }
# }
# ```
# > **Warning:**
# >   `updatedToolOutput` only changes what Claude sees. The tool has already run by the time the hook fires, so any files written, commands executed, or network requests sent have already taken effect. Telemetry such as OpenTelemetry tool spans and analytics events also captures the original output before the hook runs. To prevent or modify a tool call before it runs, use a [PreToolUse](#pretooluse) hook instead.
# >
# >   The replacement value must match the tool's output shape. Built-in tools return structured objects rather than plain strings. For example, `Bash` returns an object with `stdout`, `stderr`, `interrupted`, and `isImage` fields. For built-in tools, a value that does not match the tool's output schema is ignored and the original output is used. MCP tool output is passed through without schema validation. Stripping error details that Claude needs can cause it to proceed on a false assumption.
#
# ---------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------
# ##### AskUserQuestion
#
# Asks the user one to four multiple-choice questions.
#
# | Field       | Type   | Example                                                                                                            | Description                                                                                                                                                                                      |
# | :---------- | :----- | :----------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
# | `questions` | array  | `[{"question": "Which framework?", "header": "Framework", "options": [{"label": "React"}], "multiSelect": false}]` | Questions to present, each with a `question` string, short `header`, `options` array, and optional `multiSelect` flag                                                                            |
# | `answers`   | object | `{"Which framework?": "React"}`                                                                                    | Optional. Maps question text to the selected option label. Multi-select answers join labels with commas. Claude does not set this field; supply it via `updatedInput` to answer programmatically |
#
# ##### ExitPlanMode
#
# Presents a plan and asks the user to approve it before Claude leaves [plan mode](/en/permission-modes#analyze-before-you-edit-with-plan-mode). Claude writes the plan to a file on disk before calling the tool, so the literal `tool_input` from the model only carries `allowedPrompts`. Claude Code injects the plan content and file path before passing the input to hooks.
#
# | Field            | Type   | Example                                     | Description                                                                                                                                             |
# | :--------------- | :----- | :------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
# | `plan`           | string | `"## Refactor auth\n1. Extract..."`         | Plan content in Markdown. Injected from the plan file on disk                                                                                           |
# | `planFilePath`   | string | `"/Users/.../plans/refactor-auth.md"`       | Path to the plan file. Injected                                                                                                                         |
# | `allowedPrompts` | array  | `[{"tool": "Bash", "prompt": "run tests"}]` | Optional. Prompt-based permissions Claude is requesting to implement the plan, each with a `tool` name and a `prompt` describing the category of action |
#
# In `PostToolUse`, `tool_response` is an object with `plan` and `filePath` fields holding the approved plan, plus internal status flags. Read `tool_response.plan` for the plan content rather than re-reading the file from disk.
#
# ---------------------------------------------------------------------------------

# ── Available environment variables ──────────────────────────────────────────
# CLAUDE_PROJECT_DIR    — project root
# CLAUDE_PLUGIN_ROOT    — plugin installation directory (plugin hooks only)
# CLAUDE_PLUGIN_DATA    — plugin persistent data directory (plugin hooks only)
# CLAUDE_CODE_REMOTE    — "true" in remote web environments, unset in local CLI
# CLAUDE_EFFORT         — active effort level (low|medium|high|xhigh|max)
# ─────────────────────────────────────────────────────────────────────────────

# ---------------------------------------------------------------------------------
#   {
#     "PostToolUse": [
#       {
#         "matcher": "AskUserQuestion",
#         "hooks": [
#           {
#             "type": "command",
#             "command": ""$CLAUDE_PROJECT_DIR"/.claude/hooks/post_tool_use.d/askuserquestion.sh"
#           }
#         ]
#       }
#     ]
#   }
# ---------------------------------------------------------------------------------

HookRunLog="${GLOBAL_CLAUDE_DIR:-${HOME}/.claude}/hooks/$(date '+%Y%m%d')_run.log"
HookLogMsg="[$(date '+%s')] ${BASH_SOURCE[0]}"

echo "$HookLog" >> "$HookRunLog"


# INPUT="$(cat)"

# | `decision`             | `"block"` adds the `reason` next to the tool result.
#                                          Claude still sees the original output;
#                                          to replace it, use `updatedToolOutput` |
#
# | `reason`               | Explanation shown to Claude when `decision` is `"block"`                                                                           |
