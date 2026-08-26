---
name: graphify
description: Build or refresh the project knowledge graph when asked, then answer via MCP/CLI before raw grep.
---

# Workflow: graphify

1. **Missing graph** → do nothing unless the user asked to build. Bootstrap: `graphify update .` (AST). Full `/graphify .` only if explicitly requested.
2. **Graph exists + Survey / Documentation / Architecture task** → Mandatory L0 MCP (`query_graph`, `god_nodes`), fallback L1 `graphify query "<q>" --budget 1200`. On failure once → scoped `rg`/`fd`.
3. **Graph exists + Pinpoint fix (single line/hex)** → Bypass L0/L1, pinpoint with `rg -n`.
4. **Edit anchors & surgical edits** → `rg`/`fd`/`ast-grep` on scoped paths only → `replace_file_content`.
5. **After edits** → `just update-graph` once per batch, then `just deploy` (if configs) and `just audit`. Architecture answers: `just remember "<q>" "<a>"`. Session start: `just lessons`. WaitMs ≥ 60000 if the graph update needs it. The post-commit hook additionally auto-rebuilds on every commit.
6. **Done contract** → do not report a "fix" complete until a fail→pass executable check ran in the same batch. `just audit` PASS is regression-only.

