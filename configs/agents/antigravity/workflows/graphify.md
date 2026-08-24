---
name: graphify
description: Build or refresh the project knowledge graph when asked, then answer via MCP/CLI before raw grep.
---

# Workflow: graphify

1. **Missing graph** → do nothing unless the user asked to build. Bootstrap: `graphify update .` (AST). Full `/graphify .` only if explicitly requested.
2. **Graph exists + codebase question** → MCP if tools exist, else `graphify query "<q>" --budget 1500`. On failure once → scoped `rg`/`fd`.
3. **Edit anchors** → `rg`/`fd`/`ast-grep` on scoped paths.
4. **After edits** → `graphify update .` once per batch (WaitMs ≥ 60000 if needed).
