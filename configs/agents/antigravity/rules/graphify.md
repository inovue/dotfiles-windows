---
trigger: always_on
description: Gated graphify navigation when graphify-out exists. MCP if connected, else CLI, then scoped rg/fd/sd/ast-grep. No unsolicited bootstrap.
---

# Graphify × Antigravity Hybrid Protocol

**Gate:** If `graphify-out/graph.json` is missing → use normal `rg` / `fd` / `ast-grep` only. Do **not** run graphify, MCP graph tools, or `/graphify` unless the user explicitly asks to build a graph.

## ⚡ Deterministic Execution State Machine

```text
MODE A: Survey / Audit / QA
  1. Ground Truth -> Run `just audit` first (96+ checks + graph health). If PASS, all tools/syntax/configs are proven valid.
  2. Topology Hubs -> Run `query_graph(question="...")` OR `god_nodes` -> MUST immediately call `get_neighbors("<hub>")`.
  3. Synthesize -> Answer user. [HARD BAN: 0 file reads allowed if audit passes].

MODE B: Code Modification / Refactoring
  1. Scope -> `shortest_path` / `get_node` (find callers/callees).
  2. Locate (L2) -> Scoped `rg -n` / `ast-grep` on exact files only (max 2-3 files).
  3. Edit (L3) -> `replace_file_content`.
  4. Sync (L4) -> `just deploy` (if configs) + `just audit` + `graphify update .` (once per batch).
```

## 🛠 Exact Antigravity MCP Invocation Patterns

In Antigravity, call the `graphify` MCP server via `call_mcp_tool` or use native `just` CLI commands:

```json
// 1. Survey / God Nodes
call_mcp_tool(ServerName="graphify", ToolName="god_nodes", Arguments={"top_n": 5})

// 2. Hub Expansion (Mandatory after god_nodes or file query)
call_mcp_tool(ServerName="graphify", ToolName="get_neighbors", Arguments={"label": "<hub_name>"})

// 3. Architecture Question
call_mcp_tool(ServerName="graphify", ToolName="query_graph", Arguments={"question": "How does X work?", "depth": 1, "token_budget": 1200})

// 4. Trace Dependency Path
call_mcp_tool(ServerName="graphify", ToolName="shortest_path", Arguments={"source": "nodeA", "target": "nodeB"})
```

| Intent | MCP Tool | Required Arguments | Optional Arguments | Mandatory Next Step |
| :--- | :--- | :--- | :--- | :--- |
| **Open Survey / QA** | `query_graph` | `question: string` | `token_budget: int` (1200), `depth: int` (1), `mode: string` | Read output or synthesize. |
| **Concept / Node** | `get_node` | `label: string` | `project_path: string` | Query neighbors if node has relations. |
| **Neighborhood** | `get_neighbors` | `label: string` | `relation_filter: string`, `token_budget: int` | Expand child components or anchor L2. |
| **Path between A & B**| `shortest_path` | `source: string`, `target: string`| `max_hops: int`, `undirected: bool` | Inspect intermediate nodes. |
| **God nodes / Hubs** | `god_nodes` | *(None)* | `top_n: int`, `project_path: string` | **MUST** call `get_neighbors("<hub>")`. |

## 🔄 Continuous Mid-Stream Graphify Invariants (Active Loop)
- **Pre-Design Reflex**: Before creating a new task, function, or script, run `query_graph(question="...", token_budget=1200)` or `just graph "<topic>"` to detect existing patterns and prevent duplicated code.
- **Cross-Layer Triangulation**: When modifying orchestration (`justfile`, `install.ps1`), query neighbors of documentation hubs (`README.md`, `AGENTS.md`) and deployment (`04_setup_configs.ps1`) to ensure 100% synchronization.
- **Node Label Resilience**: AST node labels are basenames (e.g. `Microsoft.PowerShell_profile.ps1`) or symbol names. If `get_node` returns empty, immediately retry with `query_graph(question="<topic>", depth=1, token_budget=1200)` rather than falling back to grep.
- **Output Budget Enforcement**: Always pass `token_budget: 1200` to `query_graph` to ensure fast, compact inline responses without file-dump overhead.

## ❌ Hard Anti-Pattern Bans
- ❌ **1-Shot Exit Trap**: Never treat Graphify as a 1-shot entrance tool. Re-invoke Graphify whenever architectural choices, symbol collisions, or cross-layer sync arises.
- ❌ **Premature Fallback**: NEVER fall back to `rg`/`fd` scanning after only querying a file node (e.g. `README.md`) or `god_nodes`. Always expand central hubs with `get_neighbors`.
- ❌ **Post-Audit Crawling**: If `just audit` PASSES, never run manual `rg`/`fd` across scripts to re-verify already-proven facts.
- ❌ **Cascading Reads**: Max 2–3 `view_file` calls per task. 0 file reads during surveys if audit passes. Never read 4+ whole files sequentially.
- ❌ **Parameter Guessing**: Never pass `query` or `name` to MCP tools (use `question` for `query_graph`, `label` for `get_neighbors`).
- ❌ **Per-File Updates**: Run `graphify update .` **once** at the end of a coherent edit batch.
