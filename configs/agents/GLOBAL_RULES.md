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
- **Reads are a budget, not a reflex**: prefer graph queries and scoped `rg -n` snippets. When snippets already prove the answer, stop. Slice-read (max ~30 lines) only genuinely ambiguous spots; never re-read files already in context.
- **Guarantees live in hooks**: `agent_guard.py` v3 hard-blocks destructive commands with obfuscation resistance (escape-stripped rescans, flag-order-agnostic lookaheads, encoded `-enc` exec, download-and-execute in pipe AND argument form, bare profile/drive-root wipes; fail-open still raw-scans broken payloads for destructive text). Slow cmdlets, raw noisy git (missing `rtk`), unsliced reads >300 lines, and read-budget overruns get a ONE-STRIKE guidance deny (exact fix suggested; retrying the same target always passes — the guard can never deadlock the loop). Whole-file reads up to 300 lines are allowed: one read beats three slices.
- **Finish with structure**: end turns with a concise structured markdown answer, never bare tool output.

## Graph-First Navigation (when `graphify-out/graph.json` exists)

- **Gate**: no graph → plain `rg`/`fd`/`ast-grep`; never build a graph unsolicited.
- **Survey / audit**: run `just audit` first — a PASS is ground truth (100+ checks incl. graph health), so skip re-verification reads. Then discover hubs (`god_nodes` / `just hubs`) and ALWAYS expand them (`get_neighbors` / `just neighbors`) before any manual scan.
- **Modify**: scope blast radius (`shortest_path` / `get_node` / `just path`) → scoped `rg -n` on the identified files → surgical edit → `just update-graph` once per batch.
- **Review**: graph anchor (`loc=Lxx` tags) → scoped `rg -n` snippets → conclude from snippets when they suffice (Read = 0).
- **Re-invoke mid-stream**: before designing a new function/task, when syncing cross-layer files, and when a symbol lookup fails — Graphify is a continuous loop, not a one-shot entry gate.
- **Strict params**: `query_graph(question=…, token_budget=1200)`, `get_node(label=…)`, `get_neighbors(label=…)` — never `query`/`name`. Full schemas: skill `graphify-navigator`.
- **Freshness**: the post-commit hook (`just install-graph-hook`) rebuilds the graph on every commit; `just update-graph` covers uncommitted work.

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
