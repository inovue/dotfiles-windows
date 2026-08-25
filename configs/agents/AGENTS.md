# AI Agent Operational Rules & Modern Tooling Guide (SSOT)

> **Single Source of Truth (SSOT)**: Mandatory guidelines, performance invariants, and modern CLI conventions for all autonomous coding agents (Antigravity, Cursor Agent, Claude Code, Codex) operating in this workspace and Windows environment.

---

## ⚡ 1. Core Invariants & Anti-Patterns

| Category | ⚡ Mandatory Invariant | ❌ Prohibited Anti-Pattern |
| :--- | :--- | :--- |
| **Token Optimization** | Prepend `rtk` to shell commands (`rtk git status`, `rtk read`, `rtk test`, `rtk cargo test`). | Never run uncompressed noisy commands that dump massive raw output to context. |
| **Speed & Runtime** | Prefer compiled native Rust/Go CLI (`rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft`, `rtk`). | Never use slow PowerShell pipelines (`Select-String`, `Get-ChildItem -Recurse`, `Get-Content`). |
| **Read Budget** | Max **2–3 scoped files** per task (`view_file`). Zero file reads for audits when `just audit` passes. | Never sequentially read 4+ whole files or bypass budget with terminal slicing (`head`, `tail`, `bat -r`). |
| **Ground Truth** | Run `just audit` or `just test` first for surveys/audits (96+ instant checks + graph health). | Never manually grep/inspect files to verify project status when `just audit` passes. |
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
| **Token Proxy (RTK)** | Raw `git`, `test`, `build`, `cat` | `rtk [cmd]` (`rtk git status`, `rtk read`, `rtk test`) | Cuts 60-90% output tokens; failure-only tee log recovery. |
| **Content Search** | `Select-String`, `grep -r` | `rg -n "pattern" [path]` / `rtk grep` | Scoped paths only; `-l` for list, `-i` case-insensitive. |
| **File Search** | `Get-ChildItem -Recurse` | `fd "pattern" [path]` / `rtk find` | `-t f` (files), `-t d` (dirs), `-e <ext>`, `-H` (hidden). |
| **File Viewing** | `Get-Content`, `type`, `cat` | `rtk read [file]` / `bat --paging=never [file]` | Token-saving & non-interactive. |
| **Code Summary** | Manual skimming | `rtk smart [file]` | Instant 2-line heuristic summary (0 file read overhead). |
| **Line Limits** | `Get-Content -Head 20` | `head -n 20 [file]` / `tail -n 20` | Native uutils. |
| **Regex Replace** | `sed -i`, string replace | `sd 'regex' 'replacement' [file]` | In-place regex substitution. |
| **AST Refactor** | Multi-line regex / Python | `ast-grep -p 'pattern' -r 'replacement'` | Structural AST matching (JS/TS, Rust, Go, Python). |
| **JSON Query** | `ConvertFrom-Json` | `jaq '.path.key' [file.json]` / `rtk json` | Rust `jaq` (10x faster than jq; zero memory blowup). |
| **HTTP / API** | `curl`, `Invoke-WebRequest` | `xh [METHOD] [URL] [key=val]` | Auto JSON parsing, no header boilerplate. |
| **Process Inspection**| `Get-Process`, `tasklist` | `procs [query/PID/:port]` | Tree hierarchy, port bindings, memory inspection. |
| **Structural Diff** | Line `git diff` / `diff` | `rtk diff [file1] [file2]` / `difft` | AST / condensed diff (only changed lines). |
| **Directory Tree** | `tree /F`, `dir /s` | `eza --tree --level=2` / `rtk ls` | Fast directory visualization. |
| **Benchmarking** | `Measure-Command` | `hyperfine "cmd1" "cmd2"` | Statistical CLI benchmark. |
| **Token Analytics** | None / manual calculation | `rtk gain` / `rtk gain --history` | Real-time token reduction metrics & history. |
| **Binary / Hex** | `Format-Hex`, `xxd` | `hexyl [file]` | Colored byte inspection. |

---

## ⚡ 3. Deterministic Execution State Machine

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Deterministic Agent State Machine                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ MODE A: System Survey / Env QA (Zero-Crawler Protocol)                      │
│   Step 1: Ground Truth -> Run `just audit` (PASS = 100% verified + 0 junk)  │
│   Step 2: Topology Hubs -> `query_graph` OR `god_nodes` -> `get_neighbors` │
│   Step 3: Synthesis -> Present markdown report [HARD BAN: 0 file reads]     │
│                                                                             │
│ MODE B: Code Modification / Refactoring (Pinpoint Protocol)                 │
│   Step 1: Scoping -> Graphify MCP / CLI (`shortest_path` / `get_node`)      │
│   Step 2: Locate -> Scoped `rg -n` / `ast-grep` on exact files (max 2-3)    │
│   Step 3: Edit -> `replace_file_content` (surgical atomic replace)          │
│   Step 4: Verify & Sync -> Run `just deploy` + `just audit` + `just update-graph` │
│                                                                             │
│ MODE C: Deep Code Review / Security Audit (2-Tier Hybrid Protocol)          │
│   Step 1: Anchor -> `query_graph` (locate component hubs & `loc=Lxx` tags)  │
│   Step 2: Filter -> Scoped `rg -n "<patterns>" <paths>` for match snippets │
│   Step 3: Conclude -> If snippets prove safety/state: Complete (Read = 0)  │
│   Step 4: Sliced Read -> If context required: Max 1-2 files, max 30 lines   │
│           [HARD BAN: Sequential whole-file reading of 3+ files]             │
└─────────────────────────────────────────────────────────────────────────────┘
```

1. **Mode A (System Survey / QA)**:
   - **Ground Truth First**: `just audit` verifies CLI tools, env vars, SSOT sync, AST syntax, UTF-8 BOM, MCP paths, and graph topology.
   - **Zero-Crawler Ban**: If `just audit` passes, **NEVER** run `rg`, `fd`, or `view_file` across scripts to re-check already-verified facts.
   - **Mandatory 2-Step Hub-Expansion**:
     - *Step 1 (Hub Discovery)*: `god_nodes` or `query_graph(question="...")`.
     - *Step 2 (Hub Expansion)*: Call `get_neighbors("<hub_label>")` on returned hubs in the **very next step**.
     - *❌ Anti-Pattern*: Stopping after `god_nodes` or falling back to manual `rg`/`fd` scanning without expanding hubs is strictly prohibited.
2. **Mode B (Code Modification / Refactoring)**:
   - Use Graphify to determine caller/callee blast radius (prevents omissions across modules).
   - Use Graphify `loc=LXX` tags or `rg -n -C 3` to pinpoint exact lines without reading whole files.
   - Run `replace_file_content` for surgical atomic edits.
   - Run `just deploy` (if configs) + `just audit` + `just update-graph` once per batch to guarantee zero regressions.
3. **Mode C (Deep Code / Security Audit & Review - 2-Tier Hybrid Protocol)**:
   - **Step 1 (Spatial Anchor)**: Invoke Graphify MCP (`query_graph` / `get_neighbors`) to identify relevant function nodes and their exact AST line tags (`loc=Lxx`).
   - **Step 2 (Instant Pattern Match)**: Run scoped `rg -n "<pattern>" <path>` to extract match snippets.
   - **Step 3 (Snippet-First Termination - HARD RULE)**: If `rg -n` or `ast-grep` snippets confirm validation logic, defensive patterns, or implementation state, **TERMINATE TURN IMMEDIATELY WITH READ = 0**.
   - *❌ Strict Ban on "Peace of Mind" Reads*: Never call `view_file` to read entire scripts or surrounding lines after snippets have already proven safety or code logic.
   - **Step 4 (Exception Sliced Read)**: Only if snippet output is genuinely ambiguous, perform a strictly scoped sliced read (`StartLine`/`EndLine`, max 30 lines, max 1-2 files).
4. **Strict Sliced-Read Budget**:
   - Surveys / Audits: **0 file reads** permitted when `just audit` passes and `rg -n` snippets confirm implementation.
   - Code Modifications: Max 1–2 sliced reads strictly for preparing `replace_file_content` blocks.
   - Whole-file reads (>120 lines without `StartLine`/`EndLine`) are physically blocked by `agent_guard.py`.
5. **Deterministic Cybernetic Governor (`agent_guard.py`)**:
   - `PreToolUse` lifecycle hooks automatically enforce:
     - **Safety Block**: Destructive commands (`format`, `diskpart`, `rmdir /s C:\`, `git push --force (main|master)`, `curl | iex`) are hard-blocked.
     - **Modern CLI Invariant**: Slow cmdlets (`Get-ChildItem -Recurse`, `Select-String`) are blocked with instant native CLI alternatives.
     - **Read Budget Invariant**: Un-sliced reads of >120 line files and cascading reads (>4 files) are blocked.
     - **Workspace Edit Invariant**: Direct `write_to_file` with `ArtifactMetadata` on workspace source files is blocked.
6. **Context Reuse**: Never re-read files already present in context.

---

## 🧠 4. Graph-First Navigation Protocol

- **L0 Reflex**: When architectural discovery, impact analysis, or system survey is requested, invoke Graphify MCP (`call_mcp_tool` on `graphify`) or CLI (`just graph <q>` / `just hubs`) as the immediate first action.
- **Hub Expansion**: `god_nodes` discovery MUST be immediately followed by `get_neighbors("<hub>")`.
- **Continuous Mid-Stream Queries**: Never treat Graphify as a 1-shot entry tool. Query Graphify mid-stream before adding tasks/functions and during cross-layer synchronization.
- **Token Budget Rule**: Always pass `token_budget: 1200` to `query_graph` to guarantee compact inline responses.
- **Progressive Disclosure**: For exact tool schemas and parameters, see skill `graphify-navigator`.

---

## 📊 5. Output Standards & Diagrams

- **Terminal Box Diagrams (` ```text `)**: Use clean box drawing (`┌─┐`, `│`, `──►`). Japanese width 2:1.
- **Mermaid Diagrams (` ```mermaid `)**: Standard fenced code blocks.
