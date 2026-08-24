---
name: graphify-navigator
description: >-
  Graphify + Antigravity hybrid navigator. Use for codebase architecture questions,
  impact analysis, and symbol relationships ONLY when graphify-out/graph.json exists
  (or the user asks to build/refresh the graph). Combines MCP graph tools with
  ultra-fast rg/fd/sd/ast-grep locate+edit. Do not use for ordinary single-file edits
  or when no project graph is present.
---

# Graphify Navigator (Antigravity-optimized)

Turn architecture questions into **scoped subgraph answers**, then finish with **compiled CLI** pinpoint locate/edit. Optimized for Google Antigravity (MCP + always-on rules) on Windows.

## When to use

- "How does X work?", "What calls Y?", "Trace Z", "blast radius / impact of changing W"
- **Only when** `graphify-out/graph.json` exists, or the user explicitly asks to build/refresh the graph
- Avoid raw multi-file reads when the graph can answer first

## When NOT to use

- No `graphify-out/graph.json` and user did not ask for a graph → use `rg` / `fd` / `ast-grep` directly
- Ordinary pinpoint edits with a known file path → skip the graph ladder
- Do not unsolicited-run full multimodal `/graphify .` (slow, LLM cost, hang risk)

## Hot path

```text
MCP (if tools exist) → CLI graphify query → rg/fd/ast-grep locate → edit → graphify update . (once/batch)
```

### 1. Prefer MCP (when connected)

When the `graphify` MCP server exposes tools in this session:

| Intent | Tool |
| :--- | :--- |
| Open question | `query_graph` |
| One concept | `get_node` |
| Neighborhood | `get_neighbors` |
| A → B relation | `shortest_path` |

If MCP tools are missing or fail once → go to CLI. Do not retry-loop.

### 2. CLI fallback (when graph exists)

```powershell
graphify query "how does deploy work?" --budget 1500
graphify path "Install-WingetPackage" "Deploy"
graphify explain "sync_agent_rules"
graphify update .          # once per edit batch; WaitMs >= 60000 if needed
graphify god-nodes --top 15
```

### 3. Pinpoint locate + edit (after graph scoping)

```powershell
rg -n "function_name" scripts/
fd -t f -e ps1 "setup"
ast-grep -p 'function $NAME($$$A) { $$$B }' --lang ts
sd 'oldName' 'newName' path/to/file.ps1
```

## Bootstrap / refresh (user-requested only)

```powershell
# Fast code-only graph (no LLM) — preferred bootstrap
graphify update .

# Full multimodal pipeline — only when the user explicitly asks
# /graphify .
```

## Stability rules

1. Cap query tokens: always `--budget 1500` unless the user asks for more depth.
2. Do not read `GRAPH_REPORT.md` unless doing a broad architecture review.
3. Do not start with whole-repo `rg` for architectural discovery when the graph exists.
4. Do not hang on pagers — use non-interactive flags / `PAGER=cat`.
5. Missing graph + no user request to build → skip graphify entirely (normal CLI).
6. MCP unavailable → CLI once → scoped `rg`/`fd`. Never stall on missing tools.
7. Run `graphify update .` **once per edit batch**, not after every file. It can exceed 10s.
