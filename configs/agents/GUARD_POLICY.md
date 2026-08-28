# Guard Policy (Cursor-only SSOT)

> Mechanical guarantees live in `scripts/agent_guard.py` v5.1. This file is the
> human-readable table. Do not restate it in `GLOBAL_RULES.md`.
> Tunables are the named constants at the top of `agent_guard.py`.

## Topology (Cursor-only)

Cursor runs **every** matching hook source (Enterprise → Team → Project → User).
A second full guard double-counts Read crawl. Split:

| Source | Role |
| :--- | :--- |
| Project `.cursor/hooks.json` | Graph-first wall (this repo). |
| User `~/.cursor/hooks.json` | `--mode=destructive`, matcher `Shell` only. |

| Event | Role |
| :--- | :--- |
| `sessionStart` | Project only. Short additional_context. Cannot block. |
| `preToolUse` | Graph-gate, edit-gate, read budget, wait-floor, destructive deny, **rtk rewrite via `updated_input`**. |
| `beforeMCPExecution` | Record graphify MCP contact (`project_path` / query-log fallback 180s). |
| `afterFileEdit` | Record `edited` / `edited_semantic` only. Never deny (edit already landed). |
| `stop` | **Hard loop** (`loop_limit` 5): `followup_message` until `just update-graph` (+ `just semantic-merge` if docs/images) **when `graph.json` exists**. `just audit` is not a loop condition. |
| `sessionEnd` | Same contract as advisory context (fire-and-forget; cannot loop). |

Never `beforeTabFileRead` / `afterTabFileEdit`. `rtk hook cursor` is **not** a second process.

## Gates

| Gate | Trigger | Action | Escape |
| :--- | :--- | :--- | :--- |
| Destructive | format/wipe/encoded iex/force-push main | hard deny | none |
| rtk rewrite | noisy command with an rtk equivalent | allow + `updated_input` | already `rtk …` |
| rtk fallback | rewrite unavailable and git status/log/diff/show | one-strike deny | retry |
| Slow CLI | `Get-ChildItem -Recurse` / `Select-String` | one-strike deny | retry with `fd`/`rg` |
| Unsized read | >300 lines, no limit | one-strike deny | `rtk read -l aggressive` |
| Cumulative read | same file slices sum >300 | one-strike deny | stop / `rtk smart` |
| Read budget | >8 unique files / session | one-strike deny | edit resets |
| Graph-gate | unanchored `rg`/`fd`/Grep (no path or `.`), graph exists, no contact | one-strike deny | `just hubs` then retry |
| Edit-gate | first/multi-file edit, no graph contact | one-strike deny | same-file retry = pinpoint |
| Wait-floor | finite `just …` with `block_until_ms` < 120000 | one-strike deny | retry 120000 |
| PS 5.1 chain | `powershell.exe` + `&&`/`\|\|` | one-strike deny | drop wrapper |
| Hard loop | graph exists, edits without update-graph/(semantic-merge) | stop followup | run the missing `just` |

Fail-open on hook crash (except raw-payload destructive scan). One-strike can never deadlock. Glob and scoped `rg -n pat file` are not gated.

## Recovery

| Deny class | Copy-paste next step |
| :--- | :--- |
| Graph-gate | `just hubs` then `rg -n <pat> <file>` |
| Edit-gate | `just path <a> <b>` then retry the same file |
| Read | `rtk read <f> -l aggressive` or `rtk smart <f>` |
| Tokens | let rewrite land, or `rtk git status` |
| Batch end | `just update-graph` (docs: skill `graphify-builder` then `just semantic-merge`) |
