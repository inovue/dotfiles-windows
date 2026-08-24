---
trigger: always_on
description: Gated graphify navigation when graphify-out exists. MCP if connected, else CLI, then scoped rg/fd/sd/ast-grep. No unsolicited bootstrap.
---

# Graphify × Antigravity Hybrid Protocol

**Gate:** If `graphify-out/graph.json` is missing → use normal `rg` / `fd` / `ast-grep` only. Do **not** run graphify, MCP graph tools, or `/graphify` unless the user explicitly asks to build a graph.

## Ladder (when gate passes)

```text
L0  MCP   query_graph / get_node / get_neighbors / shortest_path  (if tools exist)
L1  CLI   graphify query|path|explain --budget 1500
L2  Locate rg -n / fd / ast-grep   (scoped paths ONLY)
L3  Edit  replace_file_content / sd / ast-grep -U
L4  Sync  graphify update .   (once per edit batch; AST-only)
```

1. **Architecture / impact** → L0 if MCP tools exist, else L1. Prefer wiki over raw walks. `GRAPH_REPORT.md` only for broad review.
2. **Edit anchors** → `rg -n` / `fd` / `ast-grep` on graph-scoped paths. Never `Select-String` / `Get-ChildItem -Recurse`.
3. **Edits** → surgical one-shots; bulk via `ast-grep -U` or `fd -x sd`.
4. **Freshness** → `graphify update .` **once** at the end of a coherent edit batch (not after every file). Skip if the graph was absent. Full `/graphify .` only when the user asks. `update` can take >10s — use WaitMs ≥ 60000 or finish edits first then update once.
5. **Hangs** → `PAGER=cat`, `bat --paging=never`, `git --no-pager`, `-NoProfile`.

## Hard bans

- ❌ Treating every workspace as a graphify project
- ❌ Unsolicited `/graphify .` / LLM extract mid-task
- ❌ MCP/tool retry loops — fall through L0→L1→L2 once
- ❌ Per-file `graphify update` spam
- ❌ Whole-repo grep for architecture when the graph exists
