---
trigger: always_on
description: Graph-first navigation when graphify-out exists. MCP preferred, just CLI fallback, scoped rg/fd/ast-grep for edits. No unsolicited bootstrap.
---

# Graphify × Antigravity Protocol

**Gate:** no `graphify-out/graph.json` → plain `rg`/`fd`/`ast-grep`; never run graphify, MCP graph tools, or `/graphify` unless the user explicitly asks to build a graph.
MCP invocation: `call_mcp_tool(ServerName="graphify", ToolName="query_graph", Arguments={"question": "…", "token_budget": 1200})`. Full tool schemas & recipes: skill `graphify-navigator`.

## Flow (hubs answer in 1-2 calls what 20 greps cannot)

- **Survey / audit** → `just audit` first: a PASS is verified ground truth, so skip re-checking reads. Then `god_nodes` or `query_graph` → ALWAYS expand hubs with `get_neighbors(label=…)` before any manual scan. Synthesize with 0 file reads when the audit passed.
- **Modify** → `just checkpoint` (required when ≥3 files or security-related) → blast radius with `shortest_path` / `get_node` (CLI: `just path`) → scoped `rg -n` on the 2-3 identified files → `replace_file_content` surgical edit → once per batch: `just deploy` (if configs) + `just update-graph` + `just audit` (= `graphify update .`).
- **Done contract** → a change called a "fix" is not done until a fail→pass executable check is added and run in the same batch. `just audit` PASS proves no regression, not that the fix works.
- **Independent review** → multi-file or security batches are not done until a fresh-context reviewer (reviewer subagent) is given only the diff + Done contract and reports zero findings.
- **Deep review** → graph anchor (`loc=Lxx` tags) → scoped `rg -n` snippets → conclude directly when snippets prove the point; slice-read (≤30 lines, ≤2 files) only genuine ambiguity.

## Mid-Stream Re-Invocation (Graphify is a loop, not an entry gate)

Re-query the graph before designing new functions or tasks, when syncing cross-layer files (`justfile` ↔ docs ↔ deploy scripts), and when a lookup fails (`get_node` empty → retry `query_graph(question=…)`, not grep).

## Invariants

- Params are strict: `query_graph(question=…)`, `get_node(label=…)`, `get_neighbors(label=…)` — never `query` / `name`. Node labels are file basenames or symbol names.
- Always pass `token_budget: 1200` for compact inline answers.
- Never fall back to unanchored `rg`/`fd` before hub expansion; never re-verify audit-proven facts by crawling files.
- Freshness: the post-commit hook (`just install-graph-hook`) auto-rebuilds the graph; run `just update-graph` once per edit batch for uncommitted work.
- SSOT: never edit generated mirrors — edit `configs/agents/` and run `just sync-rules`.
- Hooks are walls: `agent_guard.py` v4 one-strike-denies unanchored search and first/multi-file edits when the graph exists but no graph query has been recorded this session.
