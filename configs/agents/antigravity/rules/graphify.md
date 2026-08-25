---
trigger: always_on
description: Gated graphify navigation when graphify-out exists. MCP if connected, else CLI, then scoped rg/fd/sd/ast-grep. No unsolicited bootstrap.
---

# Graphify × Antigravity Hybrid Protocol

**Gate:** If `graphify-out/graph.json` is missing → use normal `rg` / `fd` / `ast-grep` only. Do **not** run graphify, MCP graph tools, or `/graphify` unless the user explicitly asks to build a graph.

## Ladder (when gate passes)

```text
L0  MCP   query_graph / get_node / get_neighbors / shortest_path  (try first if MCP tools exist)
          │
          └── [On ANY error / failure / tool absent] ──► IMMEDIATELY fall back to L1:
L1  CLI   graphify query "<topic>" --budget 1500  /  graphify god-nodes --top 10
L2  Locate rg -n / fd / ast-grep                                   (scoped paths ONLY)
L3  Edit  replace_file_content / sd / ast-grep -U                (atomic surgical edits)
L4  Sync  graphify update .                                       (once per edit batch; AST-only)
```

## Task Classification & Trigger Protocol

1. **System Survey & Global Overview** (README/AGENTS.md sync, architecture docs, codebase tour, dependency analysis, blast radius):
   - **Ground Truth First**: If verifying system state/documentation, run `just test` first for instant 80+ parameter ground-truth proof.
   - **MANDATORY L0/L1 Trigger**: Always start with `query_graph`, `god_nodes`, or fallback to L1 CLI (`graphify query`). Do NOT bypass Graphify merely because a single doc file is named in the user prompt.
2. **Multi-Component Feature / Refactor**:
   - **MANDATORY L0/L1 Trigger**: Use `get_node` / `shortest_path` (or `graphify path`) to map dependencies before touching files.
3. **Self-Contained Pinpoint Fix** (Single line typo, static color hex change in known file):
   - **Bypass L0/L1 directly to L2**: Use `rg -n` anchor → `replace_file_content`.

## Two-Tier Hybrid Discovery & Strict Budget
- **Tier 1 (High-Level Topology via Graphify L0/L1)**: Identify modules, public functions, caller/callee paths, and skills in 1-2 tool calls.
- **Tier 2 (Granular Detail via Native CLI L2)**: Use `rg -n` / `ast-grep` ONLY on the scoped files from Tier 1 for exact variable values, lists, and line anchors.
- **Strict Read Budget**: Max **2–3 `view_file` calls per task**. NEVER read 4+ whole files sequentially.

## Safe Workspace Editing & Batch Completion
- **Editing**: Always use `replace_file_content` for workspace files. Never pass `ArtifactMetadata` to workspace paths.
- **L4 Sync**: Run `graphify update .` **once** at the end of a coherent edit batch (not after every file). Skip if the graph was absent. Full `/graphify .` only when the user asks.

## Hard bans

- ❌ Treating every workspace as a graphify project (respect the gate)
- ❌ Skipping Graphify L0/L1 during whole-codebase survey or documentation update tasks
- ❌ Abandoning Graphify on L0 MCP error instead of falling back to L1 CLI (`graphify query` / `graphify god-nodes`)
- ❌ Sequential whole-file `view_file` cascades across 4+ files (Budget: max 2–3)
- ❌ Unsolicited `/graphify .` / LLM extract mid-task
- ❌ MCP/tool retry loops — fall through L0→L1→L2 once
- ❌ Per-file `graphify update` spam
- ❌ Forgetting `graphify update .` at the end of an edit batch when graph exists


