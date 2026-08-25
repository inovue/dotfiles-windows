---
name: graphify
description: Build or refresh the project knowledge graph when asked, then answer via MCP/CLI before raw grep.
---

# Workflow: graphify

1. **Missing graph** → do nothing unless the user asked to build. Bootstrap: `graphify update .` (AST). Full `/graphify .` only if explicitly requested.
2. **Graph exists + Survey / Documentation / Architecture task** → Mandatory L0 MCP (`query_graph`, `god_nodes`), fallback L1 `graphify query "<q>" --budget 1500`. On failure once → scoped `rg`/`fd`.
3. **Graph exists + Pinpoint fix (single line/hex)** → Bypass L0/L1, pinpoint with `rg -n`.
4. **Edit anchors & surgical edits** → `rg`/`fd`/`ast-grep` on scoped paths only → `replace_file_content`.
5. **After edits** → `graphify update .` once per batch (WaitMs ≥ 60000 if needed) before concluding.

