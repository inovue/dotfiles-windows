---
name: graphify-navigator
description: >-
  Graphify navigator (Cursor-primary). Use for codebase
  architecture questions, impact analysis, and symbol relationships ONLY when
  graphify-out/graph.json exists (or the user asks to build/refresh the graph).
  Combines MCP graph tools with ultra-fast rg/fd/sd/ast-grep locate+edit.
  Do not use for ordinary single-file edits or when no project graph is present.
---

# Graphify Navigator (Cursor-primary)

Turn architecture questions into **scoped subgraph answers**, then finish with **compiled CLI** pinpoint locate/edit. Cursor-first (MCP + `just` + `agent_guard`) on Windows.

## When to use

- **Repository Survey & Global Documentation Sync**: Updating `README.md`, `AGENTS.md`, or architecture documents to reflect whole-codebase reality.
- **Architecture & Relationship Discovery**: "How does X work?", "What calls Y?", "Trace Z pipeline", "What components exist in repo?"
- **Impact & Blast Radius Analysis**: Multi-component refactoring, changing shared types, altering runtime pipelines.
- **Gating Rule**: **Only when** `graphify-out/graph.json` exists, or the user explicitly asks to build/refresh the graph.

## When NOT to use

- No `graphify-out/graph.json` and user did not ask for a graph → use `rg` / `fd` / `ast-grep` directly.
- Strictly self-contained pinpoint fixes (e.g. single-line typo, static hex in a known file) where NO discovery of other components is required.
- **CRITICAL**: Do NOT bypass Graphify merely because a single file (like `README.md`) is mentioned if the task requires surveying the codebase.
- Do not unsolicited-run full multimodal `/graphify .` (slow, LLM cost, hang risk).

## Task Classification Matrix

| Category | Typical Prompts | Trigger Path |
| :--- | :--- | :--- |
| **A. System Survey & Documentation Sync** | "Update README to reflect codebase", "Explain architecture", "Audit repo structure" | **Mandatory L0/L1 Trigger** (`query_graph` / `god_nodes` / `just hubs`) → Scoped `rg` → `StrReplace` → `just update-graph` |
| **B. Multi-Component Feature / Refactor** | "Add command X across CLI and installer", "Refactor runtime setup", "Trace pipeline" | **Mandatory L0/L1 Trigger** (`get_node` / `shortest_path` / `just path` / `just affected`) → Scoped `ast-grep` → Edit → `just deploy` (if configs) → `just update-graph` |
| **C. Deep Code / Security Review** | "Check security of install scripts", "Review API key handling", "Audit risk patterns" | **2-Tier Hybrid Trigger** (`query_graph` / `get_neighbors` for `loc=Lxx` anchor) → Scoped `rg -n` snippet check → Conclude or sliced Read (cap 300 lines / file) |
| **D. Self-Contained Pinpoint Edit** | "Fix typo in line 42", "Change port 8080 to 9090 in config.toml" | **Bypass L0/L1** → Scoped `rg -n` → `StrReplace` |

## Hot path & 2-Step Hub Expansion

```text
L0/L1 Hub Discovery (god_nodes / just hubs) → L0 Hub Expansion (get_neighbors / just neighbors / just affected) → L2 Pinpoint (rg/ast-grep) → L3 Edit → L4 Sync
```

### The 2-Step Hub Expansion Workflow

1. **Step 1 (Hub Discovery)**:
   - MCP: `god_nodes(top_n=10)` or `get_neighbors("<root_or_file_node>")`
   - CLI: `just hubs` or `just graph "<topic>"`
   - *Outcome*: Reveals the central functional/documentation hubs (e.g. `configs_windows_terminal_settings`, `scripts_sync_agent_rules`).
2. **Step 2 (Hub Expansion)**:
   - MCP: `get_neighbors(label="<hub_name>")`
   - CLI: `just neighbors "<hub_name>"` (forward) or `just affected "<hub_name>"` (reverse blast radius)
   - *Outcome*: Unpacks child tools, functions, and cross-file dependencies in 1 round.
3. **Step 3 (Pinpoint Locate & Edit)**:
   - Use `rg -n` / `ast-grep` strictly within the files identified in Step 2.

> [!CAUTION]
> **Anti-Pattern Warning**: NEVER stop after querying only a root file node (e.g. `README.md`). If a node only returns section headers, YOU MUST expand the section hubs before falling back to manual `rg`/`fd` scanning!

### 1. Prefer MCP (when in tool loop)

| Intent | MCP Tool | Required Parameters | Optional Parameters | Example Payload |
| :--- | :--- | :--- | :--- | :--- |
| **Open Survey / QA** | `query_graph` | `question`, `project_path`, `token_budget` | `depth` (1-2), `mode` | `{"question": "How does deploy work?", "token_budget": 1200, "project_path": "<workspace root>"}` |
| **Concept / Node** | `get_node` | `label`, `project_path` | — | `{"label": "Install-WingetPackage", "project_path": "<workspace root>"}` |
| **Neighbors / Edges** | `get_neighbors` | `label`, `project_path` | `relation_filter`, `token_budget` | `{"label": "README.md", "project_path": "<workspace root>", "token_budget": 1200}` |
| **Path between A & B** | `shortest_path` | `source`, `target`, `project_path` | `max_hops`, `undirected` | `{"source": "install.ps1", "target": "deploy", "project_path": "<workspace root>"}` |
| **God nodes / Hubs** | `god_nodes` | `project_path` | `top_n` (10) | `{"top_n": 10, "project_path": "<workspace root>"}` |
| **Community Cluster** | `get_community` | `community_id`, `project_path` | `token_budget` | `{"community_id": 0, "token_budget": 1200, "project_path": "<workspace root>"}` |
| **Graph Statistics** | `graph_stats` | `project_path` | — | `{"project_path": "<workspace root>"}` |

> [!IMPORTANT]
> **MCP missing from catalog**: If graphify MCP tools are not in the session catalog, do **not** retry MCP — run `just graph` / `just hubs` once.
> **Strict MCP Parameter Rule**: `query_graph` takes `question` (not `query`); `get_node` / `get_neighbors` take `label` (not `name`). Always pass `project_path` (workspace root) and `token_budget: 1200`. User-global MCP (`~/.cursor/mcp.json`) has no pinned corpus; omitting `project_path` resolves `graphify-out/graph.json` against `$HOME`. If the tool returns `graph.json not found` or a home-directory path, do **not** retry MCP — run `just graph` / `just hubs` once.
> **Node Label Resilience**: AST labels are symbol names or file basenames. Empty `get_node` → `query_graph(question="<topic>", depth=1, token_budget=1200, project_path="<workspace root>")`, not text grep.
> **Continuous Mid-Stream Re-invocation**: Graphify is a loop, not a 1-shot gate. Re-query before adding functions, when syncing `justfile` ↔ docs, or before modifying profile configs.

### 2. Fast `just` CLI shortcuts (when in terminal loop)

```powershell
just graph "how does deploy work?"
just hubs
just neighbors "scripts_sync_agent_rules"
just path "04_setup_configs.ps1" "Deploy-WindowsTerminalConfig()"
just update-graph          # once per edit batch (AST + cached semantic rehydrate)
```

### Full CLI (use after hubs)

Prefer `just` in this repo. Do not paste `graphify --help`.

| Intent | CLI | just |
| :--- | :--- | :--- |
| Reverse blast radius | `graphify affected "X"` | `just affected` |
| Neighbors (same as `just neighbors`) | `graphify explain "X"` | `just neighbors` |
| Multigraph health | `graphify diagnose multigraph` | `just diagnose` |
| Collapsible tree HTML | `graphify tree` | `just graph-tree` |
| Token vs full-corpus | `graphify benchmark [graph.json]` | `just graph-bench` |
| Semantic pending flag | `graphify check-update .` | `just check-semantic` |
| AST watch (no LLM) | `graphify watch .` | `just watch` |
| Save Q&A to work-memory | `graphify save-result …` | `just remember` |
| Aggregate lessons | `graphify reflect` | `just lessons` |

Docs/images: skill `graphify-builder` then `just semantic-merge` (not a graphify subcommand).

## References (sidecar — load on demand, do not inline)

| Trigger | Reference |
| :--- | :--- |
| Graph query returned 0 hits / cross-language vocab / >2000 nodes | `references/query.md` (constrained query expansion) |
| Saving results, reflect, LESSONS, outcome vocabulary | `references/memory.md` (work-memory loop) |
| update vs check-update vs watch vs builder, git hooks | `references/update.md` (freshness) |
| Pending docs/images (INFERRED layer) | skill `graphify-builder` |

## Memory loop (semantic nodes accumulate automatically)

- **Session start**: `just lessons` — skim past outcomes before the first query.
- **After an architecture/impact answer**: `just remember "<q>" "<a>"`.
- **Own earlier answer proven wrong**: `graphify save-result --outcome corrected --correction "<truth>"`.
- Saved results become graph nodes on the next `just update-graph` / git hook.

### 3. Pinpoint locate + edit (after graph scoping)

```powershell
rg -n "function_name" scripts/
fd -t f -e ps1 "setup"
ast-grep -p 'function $NAME($$$A) { $$$B }' --lang ts
sd 'oldName' 'newName' path/to/file.ps1
```

## Anti-Thrashing & Stability Rules

1. **Zero-Loophole Read Policy**: Never bypass the read budget by calling Shell with `bat -r`, `head`, `tail`, or `Get-Content` to sequentially inspect slices of multiple files.
2. **Ground Truth First**: When `just audit` passes, treat environmental, AST, SSOT, graph health, and config integrity as proven fact. It does not replace graph query or scoped `rg` for the question at hand.
3. **Turn Completion**: Always present a structured markdown answer after graphify tools; never end a turn silently on a tool call.
4. **Saved Output Handling**: If `query_graph` output is saved to file, read it or use `get_neighbors` / `god_nodes` / `just graph "..."`.
5. **No Blind Pattern Guessing**: Never execute unanchored `rg` guessing names. Inspect graph nodes or AST first.
6. **Deterministic Execution**: Wrap variable-containing PowerShell one-liners in single quotes `'...'`.
7. **Cap query tokens**: Always `token_budget: 1200` unless the user asks for more depth.
8. **Batch updates + hard-loop**: Run `just update-graph` **once per edit batch**. If docs/images changed: skill `graphify-builder` then `just semantic-merge` before finishing. The **stop hook will follow up until update-graph runs — do not skip.** Post-commit hook keeps AST current across commits. A "fix" is not done until a fail→pass check ran in the same batch — `just audit` PASS proves no regression, not that the fix works.
9. **Safe Workspace Editing**: Cursor: `StrReplace`.
10. **Snippet-First Termination in Reviews**: If `rg -n` / `ast-grep` snippets confirm the point, conclude. Do not reconstruct a file via sequential slices (cumulative 300-line cap).
