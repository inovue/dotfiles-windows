# AI Agent Operational Rules & Modern Tooling Guide (SSOT)

> **Single Source of Truth (SSOT)**: Mandatory guidelines, performance invariants, and modern CLI conventions for all autonomous coding agents (Antigravity, Cursor Agent, Claude Code, Codex) operating in this workspace and Windows environment.

---

## ⚡ 1. Core Invariants & Anti-Patterns

| Category | ⚡ Mandatory Invariant | ❌ Prohibited Anti-Pattern |
| :--- | :--- | :--- |
| **Speed & Runtime** | Prefer compiled native Rust/Go CLI (`rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft`). | Never use slow PowerShell pipelines (`Select-String`, `Get-ChildItem -Recurse`, `Get-Content`). |
| **Read Budget** | Max **2–3 scoped files** per task (`view_file`). Reuse context. | Never sequentially read 4+ whole files or bypass budget with terminal slicing (`head`, `tail`, `bat -r`). |
| **Ground Truth** | Run `just test` first for surveys/audits (93+ instant checks). | Never manually grep/inspect files to verify project status when `just test` passes. |
| **Hub-Expansion** | `god_nodes` discovery MUST be immediately followed by `get_neighbors("<hub>")`. | Never stop at god_nodes/root node or fall back to manual `rg`/`fd` scanning before expanding hubs. |
| **Workspace Edits** | Always use `replace_file_content` for editing project files. | Never use `write_to_file` with `ArtifactMetadata` on workspace project files. |
| **Non-Interactive** | Enforce `--paging=never`, `--no-pager`, `-y`, `--yes`. | Never allow interactive pagers (`less`, `more`), editors (`vi`, `nano`), or unbypassable prompts. |
| **Powershell Execution** | Always supply `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. | Never run bare `powershell.exe` without flags; never use unescaped double quotes for `$vars`. |
| **SSOT Integrity** | Edit master files in `configs/agents/` then run `just sync-rules`. | Never manually edit mirrored files (`CLAUDE.md`, `.cursorrules`) directly. |
| **UTF-8 & Encoding** | All code UTF-8. `.ps1` with Japanese/CJK **MUST have UTF-8 BOM**. | Never save `.ps1` containing non-ASCII as BOM-less UTF-8 (causes PowerShell 5.1 crash). |
| **Turn Completion** | Always present structured markdown findings to the user. | Never terminate turns silently with only raw tool outputs. |

---

## 🛠 2. Tool Replacement Matrix

| Task | ❌ Slow / Risky Cmdlet | ⚡ Preferred Native Command | Flags & Best Practice |
| :--- | :--- | :--- | :--- |
| **Content Search** | `Select-String`, `grep -r` | `rg -n "pattern" [path]` | Scoped paths only; `-l` for list, `-i` case-insensitive. |
| **File Search** | `Get-ChildItem -Recurse` | `fd "pattern" [path]` | `-t f` (files), `-t d` (dirs), `-e <ext>`, `-H` (hidden). |
| **File Viewing** | `Get-Content`, `type`, `cat` | `bat --paging=never --style=plain [file]` | Token-saving & non-interactive. |
| **Line Limits** | `Get-Content -Head 20` | `head -n 20 [file]` / `tail -n 20` | Native uutils. |
| **Regex Replace** | `sed -i`, string replace | `sd 'regex' 'replacement' [file]` | In-place regex substitution. |
| **AST Refactor** | Multi-line regex / Python | `ast-grep -p 'pattern' -r 'replacement'` | Structural AST matching (JS/TS, Rust, Go, Python). |
| **JSON Query** | `ConvertFrom-Json` | `jaq '.path.key' [file.json]` | Rust `jaq` (10x faster than jq; zero memory blowup). |
| **HTTP / API** | `curl`, `Invoke-WebRequest` | `xh [METHOD] [URL] [key=val]` | Auto JSON parsing, no header boilerplate. |
| **Process Inspection**| `Get-Process`, `tasklist` | `procs [query/PID/:port]` | Tree hierarchy, port bindings, memory inspection. |
| **Structural Diff** | Line `git diff` / `diff` | `difft [file1] [file2]` | AST syntax-tree diffing (ignores cosmetic formatting). |
| **Line / Word Count** | `Measure-Object -Line` | `wc -l [file]` / `wc -w` | Byte/line counting via uutils. |
| **Sorting / Uniq** | `Sort-Object -Unique` | `sort.exe [file] \| uniq.exe` | Zero .NET object overhead. |
| **Directory Tree** | `tree /F`, `dir /s` | `eza --tree --level=2 --icons=never` | Fast directory visualization. |
| **Benchmarking** | `Measure-Command` | `hyperfine "cmd1" "cmd2"` | Statistical CLI benchmark. |
| **Binary / Hex** | `Format-Hex`, `xxd` | `hexyl [file]` | Colored byte inspection. |

---

## ⚡ 3. Deterministic Execution State Machine

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Deterministic Agent State Machine                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ MODE A: Survey / Audit / QA (Zero-Crawler Protocol)                         │
│   Step 1: Ground Truth -> Run `just test` (PASS = environment 100% verified)│
│   Step 2: Topology Hubs -> `query_graph` OR `god_nodes` -> `get_neighbors` │
│   Step 3: Synthesis -> Present markdown report [HARD BAN: Zero CLI scans]   │
│                                                                             │
│ MODE B: Code Modification / Refactoring (Pinpoint Protocol)                 │
│   Step 1: Scoping -> Graphify MCP / CLI (`shortest_path` / `get_node`)      │
│   Step 2: Locate -> Scoped `rg -n` / `ast-grep` on exact files ONLY         │
│   Step 3: Edit -> `replace_file_content` (surgical atomic replace)          │
│   Step 4: Verify & Sync -> Run `just test` + `just update-graph`            │
└─────────────────────────────────────────────────────────────────────────────┘
```

1. **Mode A (Survey / Audit)**:
   - **Ground Truth First**: `just test` verifies CLI tools, env vars, SSOT sync, AST syntax, UTF-8 BOM, and MCP paths.
   - **Zero-Crawler Ban**: If `just test` passes, **NEVER** run `rg`, `fd`, `Get-ChildItem` across scripts to re-check already-verified facts.
   - **Mandatory 2-Step Hub-Expansion**:
     - *Step 1 (Hub Discovery)*: `god_nodes` or `query_graph(question="...")`.
     - *Step 2 (Hub Expansion)*: Call `get_neighbors("<hub_label>")` on returned hubs in the **very next step**.
     - *❌ Anti-Pattern*: Stopping after `god_nodes` or falling back to manual `rg`/`fd` scanning without expanding hubs is strictly prohibited.
2. **Mode B (Code Modification / Refactoring)**:
   - Use Graphify to determine caller/callee blast radius.
   - Use `rg -n` / `ast-grep` **strictly on scoped files** to locate exact edit targets.
   - Run `replace_file_content` for editing.
   - Run `just test` and `just update-graph` once at the end of the batch.
3. **Strict 2–3 File Read Budget**: Max **2–3 scoped files** per task (`view_file`). Never read 4+ whole files sequentially. Never slice multiple files in terminal.
4. **Context Reuse**: Never re-read files already present in context.

---

## 🧠 4. Graphify Hybrid Protocol (Gated & Tool Signatures)

**Gate:** Use graphify ONLY when `graphify-out/graph.json` exists. Otherwise use `rg` / `fd` / `ast-grep`.

```text
L0  MCP   query_graph / get_node / get_neighbors / god_nodes / shortest_path
          │ (On error / tool absent -> immediately fall back to L1)
L1  CLI   graphify query "<topic>" --budget 1500  /  graphify god-nodes --top 10
L2  Locate rg -n / fd / ast-grep (scoped paths ONLY for Mode B edits)
L3  Edit  replace_file_content / sd / ast-grep -U (atomic surgical edits)
L4  Sync  graphify update . (once per edit batch; AST-only)
```

| Intent | MCP Tool | Required Parameters | Optional Parameters |
| :--- | :--- | :--- | :--- |
| **Open Survey / QA** | `query_graph` | `question: string` *(NOT query)* | `token_budget: int` (2000), `depth: int` (3), `mode: "bfs"\|"dfs"` |
| **Concept / Node** | `get_node` | `label: string` | `project_path: string` |
| **Neighborhood** | `get_neighbors` | `label: string` | `relation_filter: string`, `token_budget: int` |
| **Path between A & B**| `shortest_path` | `source: string`, `target: string`| `max_hops: int` (8), `undirected: bool` |
| **God nodes / Hubs** | `god_nodes` | *(None)* | `top_n: int` (10), `project_path: string` |
| **Community Cluster** | `get_community` | `community_id: int` | `token_budget: int` (2000), `project_path: string` |
| **Graph Statistics** | `graph_stats` | *(None)* | `project_path: string` |

- **Saved Output Handling**: If `query_graph` output is saved to file, inspect it or call `get_neighbors` / `graphify query ... --budget 1500`.

---

## 📊 5. Output Standards & Diagrams

- **Terminal Unicode Box Diagrams (` ```text `)**: Use clean box drawing (`┌─┐`, `│`, `──►`). Follow East Asian Width (2:1) for Japanese.
- **Mermaid Diagrams (` ```mermaid `)**: Standard fenced blocks rendered by `mm`.




