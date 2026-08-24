---
trigger: always_on
description: Graphify-first navigation when graphify-out exists. Prefer MCP if connected, else CLI, then scoped rg/fd/sd/ast-grep. Never bootstrap graphs unsolicited.
---

# Graphify × Antigravity Hybrid Protocol

**Gate:** Engage this protocol only when `graphify-out/graph.json` exists in the workspace. If missing, use normal `rg` / `fd` / `ast-grep` and do **not** run graphify, MCP graph tools, or `/graphify` unless the user explicitly asks to build a graph.

Goal when the gate passes: maximum speed + stability (no hangs, no token waste, no stale context).

## Decision ladder (mandatory when gate passes)

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ L0  MCP   query_graph / get_node / get_neighbors / shortest_path         │
│ L1  CLI   graphify query|path|explain --budget 1500                      │
│ L2  Locate rg -n / fd / ast-grep   (exact anchors ONLY)                  │
│ L3  Edit  replace_file_content / sd / ast-grep -U                        │
│ L4  Sync  graphify update .   (AST-only; only if graph already existed)  │
└──────────────────────────────────────────────────────────────────────────┘
```

1. **Architecture / relationships / "what calls X" / impact**
   - Prefer **MCP** `query_graph` / `get_node` / `shortest_path` when those tools are available.
   - If MCP is unavailable or fails: `graphify query "<q>" --budget 1500` (or `path` / `explain`).
   - Prefer wiki (`graphify-out/wiki/index.md`) over raw source walks when present.
   - Read `GRAPH_REPORT.md` only for broad architecture review — never as the default first step.

2. **Exact text / line anchors for edits**
   - `rg -n "literal_or_regex" path` — never `Select-String`, never `findstr`, never `grep -r`.
   - File discovery: `fd -t f -e <ext> "name"`.
   - Structural patterns: `ast-grep -p '...' --lang <lang>`.

3. **Edits**
   - Prefer one-shot surgical edits with known anchors from L0–L2.
   - Bulk rename/refactor: `ast-grep -p '...' -r '...' -U` or `fd ... -x sd 'a' 'b'`.
   - Never re-`view_file` content already in context; use `rg -n` for a single anchor line if needed.

4. **Freshness / stability**
   - After modifying code **only if** `graphify-out/graph.json` already existed: `graphify update .` (AST-only, no LLM cost).
   - Do **not** auto-bootstrap a missing graph. If the user asks to build one: prefer `graphify update .` (AST); run full `/graphify .` only when explicitly requested.
   - Prefer short synchronous CLI (`WaitMsBeforeAsync: 10000`, `-NoProfile`) over long PowerShell pipelines.
   - Never invoke interactive pagers; `PAGER=cat`, `bat --paging=never`, `git --no-pager`.

## Anti-patterns (hard ban)

- ❌ Blind whole-repo grep/search before consulting the graph for architecture questions **when the graph exists**
- ❌ Treating every workspace as a graphify project (global rule ≠ always use graphify)
- ❌ Unsolicited `/graphify .` or LLM extract mid-task
- ❌ Retry loops on missing MCP tools — fall through to L1 then L2
- ❌ `Get-Content | Select-String`, `Get-ChildItem -Recurse`, interactive `bat`/`less`
- ❌ Reading many source files to "discover" structure when `graphify-out/` exists
