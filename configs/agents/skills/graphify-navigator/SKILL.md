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
| **A. System Survey & Documentation Sync** | "Update README to reflect codebase", "Explain architecture", "Audit repo structure" | **Mandatory L0/L1 Trigger** (`query_graph` / `god_nodes`) → Scoped `rg` → `replace_file_content` → `graphify update .` |
| **B. Multi-Component Feature / Refactor** | "Add command X across CLI and installer", "Refactor runtime setup", "Trace pipeline" | **Mandatory L0/L1 Trigger** (`get_node` / `shortest_path`) → Scoped `ast-grep` → Edit → `graphify update .` |
| **C. Self-Contained Pinpoint Edit** | "Fix typo in line 42", "Change port 8080 to 9090 in config.toml" | **Bypass L0/L1** → Scoped `rg -n` → `replace_file_content` |

## Hot path & 2-Step Hub Expansion
 
 ```text
 L0/L1 Hub Discovery (god_nodes / query) → L0 Hub Expansion (get_neighbors) → L2 Pinpoint (rg/ast-grep) → L3 Edit → L4 Sync
 ```
 
 ### ⚡ The 2-Step Hub Expansion Workflow
 1. **Step 1 (Hub Discovery)**:
    - MCP: `god_nodes(top_n=10)` or `get_neighbors("<root_or_file_node>")`
    - CLI: `graphify god-nodes --top 10` or `graphify query "<topic>" --budget 1500`
    - *Outcome*: Reveals the central functional/documentation hubs (e.g. `🛠 主な同梱ツール一覧`, `📂 ディレクトリ構成`, `sync_agent_rules.ps1`).
 2. **Step 2 (Hub Expansion)**:
    - MCP: `get_neighbors(label="<hub_name>")`
    - CLI: `graphify query "<hub_name>" --budget 1500` or `graphify explain "<hub_name>"`
    - *Outcome*: Instantly unpacks all child tools, functions, and cross-file dependencies in 1 round.
 3. **Step 3 (Pinpoint Locate & Edit)**:
    - Use `rg -n` / `ast-grep` strictly within the files identified in Step 2.
 
 > [!CAUTION]
 > **Anti-Pattern Warning**: NEVER stop after querying only a root file node (e.g. `README.md`). If a node only returns section headers, YOU MUST expand the section hubs before falling back to manual `rg`/`fd` scanning!


### 1. Prefer MCP (when connected)

When the `graphify` MCP server exposes tools in this session, use exact parameter names:

| Intent | MCP Tool | Required Parameters | Optional Parameters | Example Payload |
| :--- | :--- | :--- | :--- | :--- |
| **Open Survey / QA** | `query_graph` | `question: string` *(NOT query)* | `token_budget: int` (2000), `depth: int` (3), `mode: "bfs"\|"dfs"` | `{"question": "How does deploy work?"}` |
| **Concept / Node** | `get_node` | `label: string` | `project_path: string` | `{"label": "Install-WingetPackage"}` |
| **Neighbors / Edges** | `get_neighbors` | `label: string` | `relation_filter: string`, `token_budget: int` | `{"label": "README.md"}` |
| **Path between A & B** | `shortest_path` | `source: string`, `target: string` | `max_hops: int` (8), `undirected: bool` | `{"source": "install.ps1", "target": "deploy"}` |
| **God nodes / Hubs** | `god_nodes` | *(None)* | `top_n: int` (10), `project_path: string` | `{"top_n": 10}` |
| **Community Cluster** | `get_community` | `community_id: int` | `token_budget: int` (2000), `project_path: string` | `{"community_id": 0}` |
| **Graph Statistics** | `graph_stats` | *(None)* | `project_path: string` | `{}` |

> [!IMPORTANT]
> **Strict MCP Parameter Rule**: Parameter names are strict (`query_graph` takes `question`, NOT `query`; `get_node` and `get_neighbors` take `label`, NOT `name`).
> **Immediate L1 Fallback Mandate**: If MCP tools fail with an error or are missing, **IMMEDIATELY fall back to the CLI commands below**. NEVER abandon Graphify or fall back to cascading whole-file or line-sliced CLI reads!

### 2. CLI fallback (when graph exists)

```powershell
graphify query "how does deploy work?" --budget 1500
graphify god-nodes --top 10
graphify path "Install-WingetPackage" "Deploy"
graphify explain "sync_agent_rules"
graphify update .          # once per edit batch; WaitMs >= 60000 if needed
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
# 1. Fast code-only graph (no LLM, 100% AST extraction) — preferred default bootstrap
graphify update .

# 2. Full deep semantic extraction (AST + LLM via OpenRouter/Gemini/OpenAI) — user-requested
powershell.exe -NoProfile -Command '[Environment]::GetEnvironmentVariables("User").GetEnumerator() | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Key, $_.Value, "Process") }; graphify extract .'
```

## Anti-Thrashing & Stability Rules

1. **Zero-Loophole Read Policy**: Never bypass the read budget by calling `run_command` with `bat -r`, `head`, `tail`, or `Get-Content` to sequentially inspect slices of multiple files.
2. **Ground Truth First**: When `just test` passes (e.g. 84 PASS), treat environmental, AST, and config integrity as proven fact. Do NOT manually verify every line of code with CLI commands.
3. **Turn Completion**: Always present a structured markdown answer/dashboard to the user after running graphify tools; never end a turn silently on a tool call.
4. **Saved Output Handling**: If `query_graph` output is saved to file, read the output or use specific tools (`get_neighbors`, `god_nodes`, `graphify query ... --budget 1500`) for compact direct results.
5. **No Blind Pattern Guessing**: Never execute unanchored `rg` searches guessing variable or key names. Inspect graph nodes or AST first.
6. **Deterministic Execution**: Always wrap variable-containing PowerShell one-liners in single quotes `'...'` to prevent outer shell parameter expansion.
7. **Safe MCP Lifecycle**: Never run `uv tool install --force` while `graphify-mcp` is running. Use `uv pip install --python "$env:APPDATA\uv\tools\graphifyy" <package>` for dependency updates.
8. **Cap query tokens**: Always `--budget 1500` unless the user asks for more depth.
9. **No broad file reads**: Do not read `GRAPH_REPORT.md` or start with whole-repo `rg` for architectural discovery when the graph exists.
10. **No interactive pagers**: Always ensure `PAGER=cat` and `--paging=never`.
11. **Batch updates**: Run `graphify update .` **once per edit batch**, not after every single file edit.
12. **Safe Workspace Editing**: Always use `replace_file_content` for editing workspace files. Never pass `ArtifactMetadata` to workspace file targets.

