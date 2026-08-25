---
trigger: always_on
description: Gated graphify navigation when graphify-out exists. MCP if connected, else CLI, then scoped rg/fd/sd/ast-grep. No unsolicited bootstrap.
---

# Graphify × Antigravity Hybrid Protocol

**Gate:** If `graphify-out/graph.json` is missing → use normal `rg` / `fd` / `ast-grep` only. Do **not** run graphify, MCP graph tools, or `/graphify` unless the user explicitly asks to build a graph.

## ⚡ Deterministic Execution State Machine

```text
MODE A: Survey / Audit / QA
  1. Ground Truth -> Run `just test` first (93+ checks). If PASS, all tools/syntax/configs are proven valid.
  2. Topology Hubs -> Run `query_graph(question="...")` OR `god_nodes` -> MUST immediately call `get_neighbors("<hub>")`.
  3. Synthesize -> Answer user. [HARD BAN: Zero manual `rg`/`fd` allowed if test passes].

MODE B: Code Modification / Refactoring
  1. Scope -> `shortest_path` / `get_node` (find callers/callees).
  2. Locate (L2) -> Scoped `rg -n` / `ast-grep` on exact files only.
  3. Edit (L3) -> `replace_file_content`.
  4. Sync (L4) -> `just test` + `graphify update .` (once per batch).
```

## 🛠 Exact MCP Signatures & Mandatory Transitions

| Intent | MCP Tool | Required Parameters | Optional Parameters | Mandatory Next Step |
| :--- | :--- | :--- | :--- | :--- |
| **Open Survey / QA** | `query_graph` | `question: string` *(NOT query)* | `token_budget: int` (2000), `depth: int` (3), `mode: "bfs"\|"dfs"` | Read output or synthesize. |
| **Concept / Node** | `get_node` | `label: string` | `project_path: string` | Query neighbors if node has relations. |
| **Neighborhood** | `get_neighbors` | `label: string` | `relation_filter: string`, `token_budget: int` | Expand child components or anchor L2. |
| **Path between A & B**| `shortest_path` | `source: string`, `target: string`| `max_hops: int` (8), `undirected: bool` | Inspect intermediate nodes. |
| **God nodes / Hubs** | `god_nodes` | *(None)* | `top_n: int` (10), `project_path: string` | **MUST** call `get_neighbors("<hub>")`. |
| **Community Cluster** | `get_community` | `community_id: int` | `token_budget: int` (2000), `project_path: string` | Inspect cluster members. |
| **Graph Statistics** | `graph_stats` | *(None)* | `project_path: string` | Check node/edge density. |

## ❌ Hard Anti-Pattern Bans
- ❌ **Premature Fallback**: NEVER fall back to `rg`/`fd` scanning after only querying a file node (e.g. `README.md`) or `god_nodes`. Always expand central hubs with `get_neighbors`.
- ❌ **Post-Test Crawling**: If `just test` PASSES, never run manual `rg`/`fd` across scripts to re-verify already-proven facts.
- ❌ **Cascading Reads**: Max 2–3 `view_file` calls per task. Never read 4+ whole files sequentially.
- ❌ **Parameter Guessing**: Never pass `query` or `name` to MCP tools (use `question` for `query_graph`, `label` for `get_neighbors`).
- ❌ **Per-File Updates**: Run `graphify update .` **once** at the end of a coherent edit batch.



