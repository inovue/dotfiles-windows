# Global AI Agent Rules (SSOT Master)

> Always-on rules for all coding agents (Antigravity, Cursor Agent, Claude Code, Codex) on this Windows machine.
> This layer holds only facts and invariants. Procedures live in on-demand skills — load one instead of guessing:
> `graphify-navigator` (graph query protocol), `graphify-builder` (session-bound semantic extract), `modern-cli-expert` (AST/CLI recipes), `rtk-expert` (token proxy), `browser-agent` (Chrome automation), `tui-wireframe-designer` (TUI layout and flow renderer).

## Core Invariants

- **Token economy**: prepend `rtk` to noisy commands (`rtk git status`, `rtk read <file>`, `rtk test`). Raw dumps waste 60-90% of output tokens.
- **Native CLI first**: use `rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft`, `eza`, `hyperfine` instead of PowerShell pipelines (`Select-String`, `Get-ChildItem -Recurse`, `Get-Content`). Compiled tools are 10-100x faster and their output is stable to parse.
- **PowerShell 7 host**: after `install.ps1`, Cursor automation / agent Shell / just recipes use `pwsh` (parses `&&`). `just install` and just's windows-shell stay `powershell.exe` so bootstrap works before winget installs pwsh. Do not wrap agent commands in `powershell.exe` (Windows PowerShell 5.1). Standalone `.ps1` still runs with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. Any `.ps1` containing CJK must be UTF-8 **with BOM** (5.1 still exists on the machine).
- **Non-interactive always**: `--paging=never`, `--no-pager`, `-y`; run `.ps1` with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. Pagers, editors, and prompts hang agents.
- **Encoding**: all code UTF-8. Any `.ps1` containing CJK text MUST be saved UTF-8 **with BOM** — Windows PowerShell 5.1 misparses BOM-less non-ASCII files. Antigravity `replace_file_content` strips BOM; re-apply with PowerShell if CJK `.ps1` edited.
- **SSOT flow**: edit masters under `dotfiles-windows/configs/agents/`, then run `just sync-rules`. Deployed mirrors (global AGENTS.md / CLAUDE.md / rule files) are generated; direct edits get overwritten.
- **Reads are a budget, not a reflex**: prefer graph queries and scoped `rg -n` snippets. When snippets already prove the answer, stop. Batch multi-target searches into a single `rg -e 'a' -e 'b'` pass instead of sequential lookups. Slice-read (max ~30 lines) only genuinely ambiguous spots; never re-read files already in context.
- **Cumulative read cap**: sequential slices of one file that sum past 300 lines are the same waste as an unsliced dump. Stop. Structure discovery is `rg -n '^function |^def |^class '`, `ast-grep`, or `rtk read <f> -l aggressive`.
- **Finite jobs wait in-tool**: terminating commands (`just audit`, `just test`, `just sync-rules`, `just check-rules`, `just update-graph`, `just deploy`) wait in the original shell call. Antigravity `run_command` schema caps at 10000ms; jobs exceeding 10s auto-background. Never poll (`schedule`/`manage_task status`) — yield the turn and let reactive push wake you.
- **Edit verification**: treat an edit tool's success snippet as verification; do not re-read the same file immediately after. Re-read only on edit failure, ambiguous result, or external rewrite (hook/formatter).
- **Content-addressed edits**: prefer old/new string edits. When only a line-numbered tool is available, discover all target line ranges in one pass (`rg -n -e 'a' -e 'b' <f>`), then apply same-file multi-edits Bottom-Up (highest line first) without intermediate re-reads.
- **Guarantees live in hooks**: `agent_guard.py` v4.7 hard-blocks destructive commands (v3 obfuscation resistance unchanged). Slow cmdlets, raw noisy git (missing `rtk`), unsliced reads >300 lines (Cursor `offset` 0/1 with no limit counts as unsliced), **cumulative sliced reads of one file >300 lines**, explicit `powershell.exe` (5.1) with `&&`/`||`, finite-batch jobs with an explicit short wait / background flag, and read-budget overruns get a ONE-STRIKE guidance deny. Graph-first walls: unanchored `rg`/`fd`/Grep and first/multi-file edits without a recorded graph query are one-strike denied when `graphify-out/graph.json` exists (query-log fallback is 180s, not 2h). stop/sessionEnd warns if edits lack `just update-graph` + `just audit`, or docs/images lack `just semantic-merge`. Short-wait polling tools get allow+guidance, never deny. Retry always passes — the guard can never deadlock the loop.
- **Finish with structure**: end turns with a concise structured markdown answer, never bare tool output.

## Graph-First Navigation (when `graphify-out/graph.json` exists)

- **Gate**: no graph → plain `rg`/`fd`/`ast-grep`; never build a graph unsolicited.
- **Survey / audit**: run `just audit` first — a PASS is ground truth (100+ checks incl. graph health), so skip re-verification reads. Then discover hubs (`god_nodes` / `just hubs`) and ALWAYS expand them (`get_neighbors` / `just neighbors`) before any manual scan.
- **Modify**: `just checkpoint` (required when ≥3 files or security-related) → blast radius (`shortest_path` / `get_node` / `just path`) → scoped `rg -n` on the identified files → surgical edit → `just deploy` (if configs) → `just update-graph` → `just audit`.
- **Done contract**: a change called a "fix" is not done until a fail→pass executable check is added and run in the same batch. `just audit` PASS proves no regression, not that the fix works.
- **Independent review**: multi-file or security batches are not done until a fresh-context reviewer (Bugbot / reviewer subagent) is given only the diff + this Done contract and reports zero findings.
- **Review**: graph anchor (`loc=Lxx` tags) → scoped `rg -n` snippets → conclude from snippets when they suffice (Read = 0).
- **Re-invoke mid-stream**: before designing a new function/task, when syncing cross-layer files, and when a symbol lookup fails — Graphify is a continuous loop, not a one-shot entry gate.
- **Strict params**: `query_graph(question=…, token_budget=1200, project_path=<workspace root>)`, `get_node(label=…)`, `get_neighbors(label=…)` — never `query`/`name`. Full schemas: skill `graphify-navigator`. Always pass `project_path` on MCP calls. If MCP returns `graph.json not found` or a home-directory path, do not retry MCP — run `just graph` / `just hubs` once. Never pin this repo's `graph.json` into user-global MCP. MCP contact is recorded on Cursor (`beforeMCPExecution` / `CallDynamicTool` / `MCP:<tool>`), Claude Code (`mcp__graphify__.*` PreToolUse), and Antigravity (`call_mcp_tool`); Windows Claude PreToolUse-on-MCP is flaky, so the query-log fallback covers all three.
- **Memory loop**: session start `just lessons`; after answering an architecture/impact question `just remember "<q>" "<a>"` (wrong earlier answer: `graphify save-result --outcome corrected`). Saved results become graph nodes on the next update — this is how semantic knowledge accumulates.
- **Freshness**: the post-commit hook (`just install-graph-hook`) rebuilds AST on every commit; `just update-graph` covers uncommitted work and rehydrates cached semantic nodes. `just check-semantic` / `just semantic-prepare` report pending docs/images; clear them with skill `graphify-builder` then `just semantic-merge` (session model only — never `graphify extract`).
- **Wide nav**: if `graphify-out/wiki/index.md` exists, use it for broad orientation before hub expansion.

## Tool Quick Map

| Task | Command |
| :--- | :--- |
| Content search | `rg -n "pat" <path>`. Note: Antigravity `grep_search` on a single file returns 0 results; use directory + `Includes` or `rg -n`. |
| File search | `fd "pat" -t f` |
| View / create file | `rtk read <f>` / `bat --paging=never <f>`. Note: Antigravity `write_to_file` is brain-only; workspace file creation uses `pwsh`/Python. |
| Regex replace | `sd 'a' 'b' <f>` |
| AST refactor | `ast-grep -p '<pat>' -r '<repl>'` |
| JSON query | `jaq '.k' f.json` |
| HTTP | `xh GET <url>` |
| Processes / ports | `procs <query|:port>` |
| Structural diff | `difft` / `rtk diff` |
| Directory tree | `fd -t d --max-depth 2` / native Glob. If `eza --tree`, add `--color=never --icons=never` |
| Benchmark | `hyperfine "a" "b"` |
| Token analytics | `rtk gain` |

## Background wait (all harnesses)

Finite batch jobs wait in the original shell call. After a server/watcher is started, end the turn and let the harness completion notification wake you. One long wait is only for hang-risk processes.

| Intent | Antigravity | Cursor | Claude Code |
| :--- | :--- | :--- | :--- |
| Finite job (`just audit` / `test` / `sync-rules` / `deploy`) | `WaitMsBeforeAsync` >= 10000 (schema max; auto-backgrounds >10s; do not poll) | `block_until_ms` >= 120000 | do not set `run_in_background` |
| Yield after starting a watcher | end the turn (completion push) | end the turn (unawaited-job notify) | end the turn (Bash completion notify) |
| Hang-risk monitor (dev server) | one `manage_task` / terminal read | one `AwaitShell` with a long wait or pattern | `Monitor`, or one `BashOutput` |
