---
name: graphify
description: Build or refresh the project knowledge graph when asked, then answer via MCP/CLI graph tools before raw grep.
---

# Workflow: graphify

Use this workflow when the user asks to build/refresh the graph, or when answering a codebase question and `graphify-out/graph.json` already exists.

1. **Missing graph**
   - Do nothing graphify-related unless the user asked to build it.
   - If asked to bootstrap: prefer AST-only `graphify update .` (fast, no LLM). Full multimodal `/graphify .` only when explicitly requested.
2. **Graph exists + codebase question** → query (skip rebuild):
   - Prefer MCP when tools are available: `query_graph` / `get_node` / `shortest_path`
   - Fallback CLI: `graphify query "<question>" --budget 1500`
   - If MCP/CLI fail once → fall through to scoped `rg` / `fd` (no retry loops)
3. **Edit anchors** after graph hits → `rg -n` / `fd` / `ast-grep` only on scoped paths.
4. **After code edits** (only if the graph already existed) → `graphify update .`.
