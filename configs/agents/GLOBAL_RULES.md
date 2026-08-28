# Global AI Agent Rules (SSOT Master)

> Cursor-only always-on rules on this Windows machine. Procedures live in skills — load one instead of guessing:
> `graphify-navigator`, `graphify-builder`, `modern-cli-expert`, `rtk-expert`.
> Gate table: `configs/agents/GUARD_POLICY.md`. Baseline: `configs/agents/HARNESS_BASELINE.md`. Pins: `configs/pins.json`.

## Core Invariants

- **Harness baseline**: provisioned by `just install` / `just setup-harness`. Agent Shell is `pwsh -NoProfile -NonInteractive`. Hooks, PATH (`~/.local/bin`), UTF-8, MCP, and pinned graphify/rtk are fixed. **Do not reconfigure** `settings.json`, shell profiles, or Windows PATH unless the user asks.
- **Token economy**: hooks rewrite noisy shell via `rtk rewrite` (`updated_input`). Prefer native Read/Grep. Use `rtk read -l aggressive` / `rtk smart` only for files over the 300-line cap. Do not dump raw git/test output.
- **Native CLI first**: `rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft` — not PowerShell pipelines (`Select-String`, `Get-ChildItem -Recurse`).
- **PowerShell 7 host**: after install, agent Shell and just recipes use `pwsh` (parses `&&`). `just install` stays `powershell.exe` for bootstrap. Never wrap agent commands in `powershell.exe` (5.1). CJK `.ps1` must be UTF-8 with BOM.
- **Non-interactive always**: `--paging=never`, `--no-pager`, `-y`; run `.ps1` with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
- **SSOT**: edit `configs/agents/`, then `just sync-rules` (Cursor targets only). Deployed mirrors are generated.
- **Reads are a budget**: graph + scoped `rg -n` first. Slice only when snippets are ambiguous. Cumulative 300-line cap per file.
- **Finite jobs**: `block_until_ms >= 120000` for `just audit|test|sync-rules|update-graph|deploy`. Never poll. After starting a watcher, end the turn.
- **Guarantees live in hooks**: `GUARD_POLICY.md`. Destructive = hard deny. Graph-gate / read-budget / wait-floor = one-strike. Stop **hard-loops** (limit 5) until `just update-graph` (+ `just semantic-merge` if docs) when a graph exists. Same-target retry always passes except destructive.
- **Finish with structure**: concise markdown, never bare tool output.

## Graph-First Navigation (only when `graphify-out/graph.json` exists)

- **Survey**: `just hubs` then `just neighbors` / `just affected`, then scoped `rg`. Do not start with `just audit`.
- **Modify**: `just checkpoint` if ≥3 files or security → `just path` / `just affected` → scoped `rg -n` → edit → `just deploy` (configs) → `just update-graph`. `just audit` is the Done contract (regression), not a survey.
- **Done contract**: a "fix" needs a fail→pass check in the same batch. `just audit` PASS proves no regression, not that the fix works.
- **Independent review**: multi-file or security batches need a fresh-context reviewer on the diff + Done contract.
- **Re-invoke**: Graphify is a loop. Empty `get_node` → `just graph "<q>"`, not grep. MCP: `query_graph(question=…, token_budget=1200, project_path=<workspace root>)`. If MCP misses or pins `$HOME`, do not retry MCP — `just graph` / `just hubs`. Never pin this repo's `graph.json` in `~/.cursor/mcp.json`.
- **Memory**: session start `just lessons`; after architecture answers `just remember "<q>" "<a>"`. Wrong earlier answer: `graphify save-result --outcome corrected`.
- **Freshness**: post-commit hook rebuilds AST. Uncommitted work: `just update-graph`. Docs/images: skill `graphify-builder` then `just semantic-merge` (never `graphify extract`). Wiki: `graphify-out/wiki/index.md` when present.

## Tool Quick Map

| Task | Command |
| :--- | :--- |
| Content search | `rg -n "pat" <path>` |
| File search | `fd "pat" -t f` |
| View | Read (native) / `rtk read <f>` if >300 lines |
| Replace / AST | `sd` / `ast-grep` |
| JSON / HTTP | `jaq` / `xh` |
| Graph | `just graph` `just hubs` `just neighbors` `just path` `just affected` `just diagnose` |
| Tokens | `rtk gain` |
