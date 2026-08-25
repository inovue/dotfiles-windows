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

## Hot path

```text
MCP (if tools exist) → CLI graphify query → rg/fd/ast-grep locate (scoped) → replace_file_content → graphify update . (once/batch)
```


### 1. Prefer MCP (when connected)

When the `graphify` MCP server exposes tools in this session:

| Intent | Tool |
| :--- | :--- |
| Open question / Survey | `query_graph` |
| One concept / Module | `get_node` |
| Neighborhood | `get_neighbors` |
| A → B relation | `shortest_path` |
| God nodes / Hubs | `god_nodes` |

> [!IMPORTANT]
> **Immediate L1 Fallback Mandate**: If MCP tools fail with an error or are missing, **IMMEDIATELY fall back to the CLI commands below**. NEVER give up on Graphify or fall back to cascading whole-file `view_file` reads!

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

## Stability rules

1. **Turn Completion**: Always present a structured markdown answer/dashboard to the user after running graphify tools; never end a turn silently on a tool call.
2. **Deterministic Execution**: Always wrap variable-containing PowerShell one-liners in single quotes `'...'` to prevent outer shell parameter expansion.
3. **Safe MCP Lifecycle**: Never run `uv tool install --force` while `graphify-mcp` is running. Use `uv pip install --python "$env:APPDATA\uv\tools\graphifyy" <package>` for dependency updates.
4. **Cap query tokens**: Always `--budget 1500` unless the user asks for more depth.
5. **No broad file reads**: Do not read `GRAPH_REPORT.md` or start with whole-repo `rg` for architectural discovery when the graph exists.
6. **No interactive pagers**: Always ensure `PAGER=cat` and `--paging=never`.
7. **Batch updates**: Run `graphify update .` **once per edit batch**, not after every single file edit.
8. **Safe Workspace Editing**: Always use `replace_file_content` for editing workspace files. Never pass `ArtifactMetadata` to workspace file targets.

