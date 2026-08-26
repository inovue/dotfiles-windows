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

- **Repository Survey & Global Documentation Sync**: Updating `README.md`, `AGENTS.md`, or architecture documents to reflect whole-codebase reality.
- **Architecture & Relationship Discovery**: "How does X work?", "What calls Y?", "Trace Z pipeline", "What components exist in repo?"
- **Impact & Blast Radius Analysis**: Multi-component refactoring, changing shared types, altering runtime pipelines.
- **Gating Rule**: **Only when** `graphify-out/graph.json` exists, or the user explicitly asks to build/refresh the graph.

## When NOT to use

- No `graphify-out/graph.json` and user did not ask for a graph → use `rg` / `fd` / `ast-grep` directly.
- Strictly self-contained pinpoint fixes (e.g. single-line typo fix, static color hex change in known file) where NO discovery of other components is required.
- **CRITICAL**: Do NOT bypass Graphify merely because a single file (like `README.md`) is mentioned in the prompt if the task requires surveying the codebase!
- Do not unsolicited-run full multimodal `/graphify .` (slow, LLM cost, hang risk).

## Task Classification Matrix

| Category | Typical Prompts | Trigger Path |
| :--- | :--- | :--- |
| **A. System Survey & Documentation Sync** | "Update README to reflect codebase", "Explain architecture", "Audit repo structure" | **Mandatory L0/L1 Trigger** (`query_graph` / `god_nodes` / `just hubs`) → Scoped `rg` → `replace_file_content` → `just update-graph` → `just audit` |
| **B. Multi-Component Feature / Refactor** | "Add command X across CLI and installer", "Refactor runtime setup", "Trace pipeline" | **Mandatory L0/L1 Trigger** (`get_node` / `shortest_path` / `just path`) → Scoped `ast-grep` → Edit → `just deploy` (if configs) → `just update-graph` → `just audit` |
| **C. Deep Code / Security Review** | "Check security of install scripts", "Review API key handling", "Audit risk patterns" | **2-Tier Hybrid Trigger** (`query_graph` / `get_neighbors` for `loc=Lxx` anchor) → Scoped `rg -n` snippet check → Conclude (Read=0) or Sliced Read (max 30 lines) |
| **D. Self-Contained Pinpoint Edit** | "Fix typo in line 42", "Change port 8080 to 9090 in config.toml" | **Bypass L0/L1** → Scoped `rg -n` → `replace_file_content` |

## Hot path & 2-Step Hub Expansion
 
 ```text
 L0/L1 Hub Discovery (god_nodes / just hubs) → L0 Hub Expansion (get_neighbors / just neighbors) → L2 Pinpoint (rg/ast-grep) → L3 Edit → L4 Sync
 ```
 
 ### ⚡ The 2-Step Hub Expansion Workflow
 1. **Step 1 (Hub Discovery)**:
    - MCP: `god_nodes(top_n=10)` or `get_neighbors("<root_or_file_node>")`
    - CLI: `just hubs` or `just graph "<topic>"`
    - *Outcome*: Reveals the central functional/documentation hubs (e.g. `configs_windows_terminal_settings`, `scripts_sync_agent_rules`).
 2. **Step 2 (Hub Expansion)**:
    - MCP: `get_neighbors(label="<hub_name>")`
    - CLI: `just neighbors "<hub_name>"` or `graphify explain "<hub_name>"`
    - *Outcome*: Instantly unpacks all child tools, functions, and cross-file dependencies in 1 round.
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
> **Strict MCP Parameter Rule**: Parameter names are strict (`query_graph` takes `question`, NOT `query`; `get_node` and `get_neighbors` take `label`, NOT `name`). Always pass `project_path` (workspace root). User-global MCP (Cursor `~/.cursor/mcp.json`) has no pinned corpus; omitting `project_path` resolves `graphify-out/graph.json` against `$HOME`. If the tool returns `graph.json not found` or a home-directory path, do **not** retry MCP — run `just graph` / `just hubs` once.
> **Node Label Resilience**: AST node labels are symbol names or file basenames (e.g. `Microsoft.PowerShell_profile.ps1`, `01_winget_packages.ps1`). If `get_node` returns empty, immediately call `query_graph(question="<topic>", depth=1, token_budget=1200, project_path="<workspace root>")` rather than falling back to text grep.
> **Continuous Mid-Stream Re-invocation**: Never treat Graphify as a 1-shot entry gate. Call Graphify mid-task before adding new functions, when checking cross-layer sync between `justfile` and `README.md`, or before modifying existing profile configurations.

### 2. Fast `just` CLI shortcuts (when in terminal loop)

```powershell
just lessons               # session start: reflect --if-stale + print LESSONS.md
just graph "how does deploy work?"
just hubs
just neighbors "scripts_sync_agent_rules"
just path "04_setup_configs.ps1" "Deploy-WindowsTerminalConfig()"
just update-graph          # once per edit batch (AST-only, no LLM)
just remember "<question>" "<answer>"   # after answering an architecture question
just check-semantic        # is semantic re-extraction pending? (needs_update flag)
```

## References (sidecar — load on demand, do not inline)

| Trigger | Reference |
| :--- | :--- |
| Graph query returned 0 hits / cross-language vocab / >2000 nodes | `references/query.md` (constrained query expansion) |
| Saving results, reflect, LESSONS, outcome vocabulary | `references/memory.md` (work-memory loop) |
| update vs check-update vs watch vs extract, git hooks, LLM backends | `references/update.md` (freshness) |

## Memory loop (semantic nodes accumulate automatically)

- **Session start**: `just lessons` — skim past outcomes before the first query.
- **After an architecture/impact answer**: `just remember "<q>" "<a>"` (full control: `graphify save-result --nodes … --outcome useful`).
- **Own earlier answer proven wrong**: `graphify save-result --outcome corrected --correction "<truth>"`.
- Saved results become graph nodes on the next update — the loop is closed by `just update-graph`/git hooks.

### 3. Pinpoint locate + edit (after graph scoping)

```powershell
rg -n "function_name" scripts/
fd -t f -e ps1 "setup"
ast-grep -p 'function $NAME($$$A) { $$$B }' --lang ts
sd 'oldName' 'newName' path/to/file.ps1
```

## Anti-Thrashing & Stability Rules

1. **Zero-Loophole Read Policy**: Never bypass the read budget by calling `run_command` with `bat -r`, `head`, `tail`, or `Get-Content` to sequentially inspect slices of multiple files.
2. **Ground Truth First**: When `just audit` passes (e.g. 97+ PASS), treat environmental, AST, SSOT, graph health, and config integrity as proven fact. Zero file reading permitted for surveys/audits.
3. **Turn Completion**: Always present a structured markdown answer/dashboard to the user after running graphify tools; never end a turn silently on a tool call.
4. **Saved Output Handling**: If `query_graph` output is saved to file, read the output or use specific tools (`get_neighbors`, `god_nodes`, `just graph "..."`) for compact direct results.
5. **No Blind Pattern Guessing**: Never execute unanchored `rg` searches guessing variable or key names. Inspect graph nodes or AST first.
6. **Deterministic Execution**: Always wrap variable-containing PowerShell one-liners in single quotes `'...'` to prevent outer shell parameter expansion.
7. **Cap query tokens**: Always `token_budget: 1200` unless the user asks for more depth.
8. **Batch updates**: Run `just update-graph` **once per edit batch**, then `just audit`. Not after every single file edit. The post-commit git hook (`just install-graph-hook` → `graphify hook install`) keeps the graph current across commits automatically; the batch update only needs to cover uncommitted work. A change called a "fix" is not done until a fail→pass executable check ran in the same batch — `just audit` PASS proves no regression, not that the fix works.
9. **Safe Workspace Editing**: Always use `replace_file_content` for editing workspace files. Never pass `ArtifactMetadata` to workspace file targets.
10. **Snippet-First Termination in Reviews**: When auditing code safety or implementation logic, if `rg -n` or `ast-grep` snippets confirm validation presence or state, conclude immediately with Read=0. Never call `view_file` sequentially just to view surrounding context.
