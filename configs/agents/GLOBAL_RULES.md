# Global AI Agent Rules (SSOT Master)

> Always-on rules for all coding agents (Antigravity, Cursor Agent, Claude Code, Codex) on this Windows machine.
> This layer holds only facts and invariants. Procedures live in on-demand skills — load one instead of guessing:
> `graphify-navigator` (graph tool schemas & navigation protocol), `modern-cli-expert` (AST/CLI recipes), `rtk-expert` (token proxy), `browser-agent` (Chrome automation).

## Core Invariants

- **Token economy**: prepend `rtk` to noisy commands (`rtk git status`, `rtk read <file>`, `rtk test`). Raw dumps waste 60-90% of output tokens.
- **Native CLI first**: use `rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft`, `eza`, `hyperfine` instead of PowerShell pipelines (`Select-String`, `Get-ChildItem -Recurse`, `Get-Content`). Compiled tools are 10-100x faster and their output is stable to parse.
- **Non-interactive always**: `--paging=never`, `--no-pager`, `-y`; run `.ps1` with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. Pagers, editors, and prompts hang agents.
- **Encoding**: all code UTF-8. Any `.ps1` containing CJK text MUST be saved UTF-8 **with BOM** — Windows PowerShell 5.1 misparses BOM-less non-ASCII files.
- **SSOT flow**: edit masters under `dotfiles-windows/configs/agents/`, then run `just sync-rules`. Deployed mirrors (global AGENTS.md / CLAUDE.md / rule files) are generated; direct edits get overwritten.
- **Reads are a budget, not a reflex**: prefer graph queries and scoped `rg -n` snippets. When snippets already prove the answer, stop. Batch multi-target searches into a single `rg -e 'a' -e 'b'` pass instead of sequential lookups. Slice-read (max ~30 lines) only genuinely ambiguous spots; never re-read files already in context.
- **Cumulative read cap**: sequential slices of one file that sum past 300 lines are the same waste as an unsliced dump. Stop. Structure discovery is `rg -n '^function |^def |^class '`, `ast-grep`, or `rtk read <f> -l aggressive`.
- **Finite jobs wait in-tool**: terminating commands (`just audit`, `just test`, `just sync-rules`, `just check-rules`, `just update-graph`, `just deploy`) wait in the original shell call. Do not background them and poll for completion. Dev servers and `just watch` are the exception.
- **Edit verification**: treat an edit tool's success snippet as verification; do not re-read the same file immediately after. Re-read only on edit failure, ambiguous result, or external rewrite (hook/formatter).
- **Content-addressed edits**: prefer old/new string edits. When only a line-numbered tool is available, discover all target line ranges in one pass (`rg -n -e 'a' -e 'b' <f>`), then apply same-file multi-edits Bottom-Up (highest line first) without intermediate re-reads.
- **Guarantees live in hooks**: `agent_guard.py` v4.4 hard-blocks destructive commands (v3 obfuscation resistance unchanged). Slow cmdlets, raw noisy git (missing `rtk`), unsliced reads >300 lines, **cumulative sliced reads of one file >300 lines**, finite-batch jobs with an explicit short wait / background flag, and read-budget overruns get a ONE-STRIKE guidance deny. Graph-first walls: unanchored `rg`/`fd`/Grep and first/multi-file edits without a recorded graph query are one-strike denied when `graphify-out/graph.json` exists; stop/sessionEnd warns if edits lack `just update-graph` + `just audit`. Short-wait polling tools get allow+guidance, never deny. Retry always passes — the guard can never deadlock the loop.
- **Finish with structure**: end turns with a concise structured markdown answer, never bare tool output.

## Graph-First Navigation (when `graphify-out/graph.json` exists)

- **Gate**: no graph → plain `rg`/`fd`/`ast-grep`; never build a graph unsolicited.
- **Survey / audit**: run `just audit` first — a PASS is ground truth (100+ checks incl. graph health), so skip re-verification reads. Then discover hubs (`god_nodes` / `just hubs`) and ALWAYS expand them (`get_neighbors` / `just neighbors`) before any manual scan.
- **Modify**: `just checkpoint` (required when ≥3 files or security-related) → blast radius (`shortest_path` / `get_node` / `just path`) → scoped `rg -n` on the identified files → surgical edit → `just deploy` (if configs) → `just update-graph` → `just audit`.
- **Done contract**: a change called a "fix" is not done until a fail→pass executable check is added and run in the same batch. `just audit` PASS proves no regression, not that the fix works.
- **Independent review**: multi-file or security batches are not done until a fresh-context reviewer (Bugbot / reviewer subagent) is given only the diff + this Done contract and reports zero findings.
- **Review**: graph anchor (`loc=Lxx` tags) → scoped `rg -n` snippets → conclude from snippets when they suffice (Read = 0).
- **Re-invoke mid-stream**: before designing a new function/task, when syncing cross-layer files, and when a symbol lookup fails — Graphify is a continuous loop, not a one-shot entry gate.
- **Strict params**: `query_graph(question=…, token_budget=1200)`, `get_node(label=…)`, `get_neighbors(label=…)` — never `query`/`name`. Full schemas: skill `graphify-navigator`. MCP contact is recorded on Cursor (`beforeMCPExecution` / `CallDynamicTool` / `MCP:<tool>`), Claude Code (`mcp__graphify__.*` PreToolUse), and Antigravity (`call_mcp_tool`); Windows Claude PreToolUse-on-MCP is flaky, so the query-log fallback covers all three.
- **Memory loop**: session start `just lessons`; after answering an architecture/impact question `just remember "<q>" "<a>"` (wrong earlier answer: `graphify save-result --outcome corrected`). Saved results become graph nodes on the next update — this is how semantic knowledge accumulates.
- **Freshness**: the post-commit hook (`just install-graph-hook`) rebuilds the graph on every commit; `just update-graph` covers uncommitted work. `just check-semantic` reports pending semantic re-extraction (docs/images/memory); clear it with `just update-semantic`, or `just watch` (set `GRAPHIFY_SEMANTIC_AUTO=1` to auto-run the LLM pass).
- **Wide nav**: if `graphify-out/wiki/index.md` exists, use it for broad orientation before hub expansion.

## Tool Quick Map

| Task | Command |
| :--- | :--- |
| Content search | `rg -n "pat" <path>` |
| File search | `fd "pat" -t f` |
| View file | `rtk read <f>` / `bat --paging=never <f>` |
| Regex replace | `sd 'a' 'b' <f>` |
| AST refactor | `ast-grep -p '<pat>' -r '<repl>'` |
| JSON query | `jaq '.k' f.json` |
| HTTP | `xh GET <url>` |
| Processes / ports | `procs <query|:port>` |
| Structural diff | `difft` / `rtk diff` |
| Directory tree | `eza --tree --level=2` |
| Benchmark | `hyperfine "a" "b"` |
| Token analytics | `rtk gain` |

## Background wait (all harnesses)

Finite batch jobs wait in the original shell call. After a server/watcher is started, end the turn and let the harness completion notification wake you. One long wait is only for hang-risk processes.

| Intent | Antigravity | Cursor | Claude Code |
| :--- | :--- | :--- | :--- |
| Finite job (`just audit` / `test` / `sync-rules` / `deploy`) | `WaitMsBeforeAsync` >= 120000 | `block_until_ms` >= 120000 | do not set `run_in_background` |
| Yield after starting a watcher | end the turn (completion push) | end the turn (unawaited-job notify) | end the turn (Bash completion notify) |
| Hang-risk monitor (dev server) | one `manage_task` / terminal read | one `AwaitShell` with a long wait or pattern | `Monitor`, or one `BashOutput` |
