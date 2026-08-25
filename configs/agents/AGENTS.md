# AI Agent Operational Rules & Modern Tooling Guide (SSOT)

> **Single Source of Truth (SSOT)**: This document defines mandatory guidelines, performance rules, and CLI conventions for all autonomous coding agents (Antigravity CLI, Cursor Agent, Claude Code, Codex CLI, etc.) operating in this workspace and across this Windows environment.

---

## ⚡ 1. Core Directives & Performance Principles

1. **Extreme Speed & Low Latency First**:
   - Always prefer **compiled, native Rust/Go CLI utilities** (`rg`, `fd`, `sd`, `ast-grep`, `bat`, `jaq`/`jq`, `xh`, `procs`, `difft`, `uutils-coreutils`) over slow, interpreted commands or heavy PowerShell cmdlets.
   - Streaming raw byte streams is 10x to 100x faster and consumes a fraction of the memory compared to PowerShell .NET object pipelines.

2. **Strict Read Budget & Zero-Cascade Guarantee**:
   - Limit `view_file` calls to a maximum of **2–3 scoped files per task**.
   - NEVER sequentially read whole files across 4+ files. For repository surveys, architecture investigations, or documentation verification, use **Graphify (L0 MCP / L1 CLI) + Scoped `rg -n` + `just test`** instead.

3. **Non-Interactive & Zero-Hang Guarantee**:
   - Never allow commands to invoke interactive pagers (`less`, `more`, interactive `bat`, interactive `git diff`).
   - Always supply non-interactive / bypass flags (`--paging=never`, `--no-pager`, `-y`, `--yes`, `--force`) when executing terminal tools.

4. **Deterministic UTF-8 Text Processing**:
   - Assume all code and text files are UTF-8. Avoid tools that output legacy Windows codepages (Shift-JIS/CP932) or add unexpected UTF-16 BOMs.

5. **Turn Completion & Zero-Silent-Exit Protocol**:
   - Every tool execution sequence MUST conclude with a clear, structured markdown response or actionable findings to the user. Never terminate an agent turn silently with only tool step results.

6. **Deterministic Windows Execution & Safe Process Lifecycle**:
   - Wrap variable-containing PowerShell one-liners in single quotes (`powershell.exe -NoProfile -Command '...'`) to prevent caller-shell variable expansion.
   - Never run destructive binary reinstallations (`uv tool install --force`) against active, locked background processes (e.g., live MCP servers); use `uv pip install --python <venv_path> <package>` for in-place dependency updates.

---

## 🛠 2. Tool Replacement Matrix & Preferred Commands

Use the following modern tools for file system inspection, searching, refactoring, and data processing:

| Task | ❌ Anti-Pattern (Slow / Risky) | ⚡ Preferred Modern Command | Notes & Flags |
| :--- | :--- | :--- | :--- |
| **Content Search** | `Select-String`, `findstr`, `grep -r` | `rg -n "pattern" [path]` | Use `rg -l` for file paths only, `rg -i` for case-insensitive, `rg -t <type>` for language filters. |
| **File / Dir Search** | `Get-ChildItem -Recurse`, `find . -name` | `fd "pattern" [path]` | Use `fd -t f` (files), `fd -t d` (dirs), `fd -e <ext>` (extensions), `fd -H` (hidden). |
| **File Viewing** | `Get-Content`, `type`, `cat`, `more` | `bat --paging=never --style=plain [file]` | `--paging=never` prevents terminal hangs; `--style=plain` saves tokens. |
| **Line Limits** | `Get-Content -Head 20` | `head -n 20 [file]` / `tail -n 20 [file]` | Powered by native `uutils-coreutils`. |
| **Text Replace** | `sed -i "s/a/b/g"`, custom scripts | `sd 'regex_find' 'replacement' [file]` | Ultra-fast in-place regex substitution without escaping headaches. |
| **AST / Code Refactor** | Multi-line regex grep / Python scripts | `ast-grep -p 'pattern' -r 'replacement'` | Syntax-tree aware search & replace across JS/TS, Python, Rust, Go, HTML, CSS. |
| **JSON Querying** | `ConvertFrom-Json`, custom node scripts | `jaq '.path.to.key' [file.json]` / `jq` | `jaq` (Rust) is 10x faster than C jq; zero-dependency stream parsing. |
| **HTTP / API Queries** | `curl -X POST -H ...`, `Invoke-WebRequest` | `xh [METHOD] [URL] [key=val]` | Ultra-fast Rust HTTP client; auto JSON parsing, clean syntax, no header boilerplate. |
| **Process Inspection** | `Get-Process`, `tasklist`, `ps` | `procs [query/PID/port]` | Instant PID, tree hierarchy, port binding (`procs :8080`), and memory inspection. |
| **Syntax Tree Diff** | Line-based `git diff` / `diff` | `difft [file1] [file2]` | AST-aware structural diffing; ignores cosmetic whitespace/formatting changes. |
| **Line / Word Count** | `Measure-Object -Line` | `wc -l [file]` / `wc -w [file]` | Fast byte/line counting via uutils. |
| **Sorting / Uniq** | `Sort-Object -Unique` | `sort.exe [file] \| uniq.exe` | Avoid PowerShell object overhead. |
| **Directory Tree** | `tree /F`, `dir /s` | `eza --tree --level=2 --icons=never` | Fast directory visualization. |
| **Benchmarking** | `Measure-Command` | `hyperfine "cmd1" "cmd2"` | Accurate, statistical CLI performance measurement. |
| **Binary / Hex View** | `Format-Hex`, `xxd` | `hexyl [file]` | Colored byte inspection. |

---

- ❌ **NEVER** sequentially read multiple whole files with `view_file` (Budget: max 2–3 files). For surveys or multi-file tasks, use Graphify (L0 MCP / L1 CLI) + `rg -n` + `just test`.
- ❌ **NEVER** abandon Graphify when L0 MCP fails. Immediately execute L1 CLI (`graphify query "<topic>" --budget 1500` or `graphify god-nodes --top 10`).
- ❌ **NEVER** manually read multiple source files to verify project status when an automated test suite (`just test`) exists. Run `just test` first.
- ❌ **NEVER** use `write_to_file` with `ArtifactMetadata` on workspace project files. `ArtifactMetadata` is strictly for `<appDataDir>\brain\<conversation-id>/...` artifacts. Always use `replace_file_content` for editing/overwriting workspace files.
- ❌ **NEVER** pipe `Get-Content` into `Select-String` (e.g. `Get-Content file.txt | Select-String "foo"`). This loads the entire file into .NET objects in memory. Always use `rg "foo" file.txt`.
- ❌ **NEVER** use `Get-ChildItem -Recurse -Filter *.ext`. Always use `fd -e ext`.
- ❌ **NEVER** use `read_url_content` on GitHub repository web pages (e.g. `https://github.com/user/repo`). This returns 300KB+ of heavy HTML/JS/CSS, wastes tokens, and truncates the README. Use `gh repo view` or `git clone --depth 1` instead.
- ❌ **NEVER** re-read (`view_file`) the same file multiple times across turns when the content is already in your conversation context. Reuse existing context or pinpoint lines with `rg -n`.
- ❌ **NEVER** manually edit mirrored documentation files (`CLAUDE.md`, `.cursorrules`, etc.) individually. Always edit the master SSOT (`configs/agents/AGENTS.md` for global rules, `AGENTS.md` for workspace rules) and run `just sync-rules`.
- ❌ **NEVER** finish an edit batch in a graph-enabled repository without running `graphify update .`.
- ❌ **NEVER** run commands that wait for user confirmation without an automatic yes flag (e.g., use `winget install --silent --accept-package-agreements`, `npm init -y`, `rm -Force`, `herdr plugin install ... --yes`).
- ❌ **NEVER** leave pagers enabled on `git diff` or `git log`. Always use `git --no-pager diff` or set `GIT_PAGER=cat`.
- ❌ **NEVER** use interactive editors (`vi`, `vim`, `nano`, `helix`) or launch interactive TUI tools (`lazygit`, `herdr`, `btm`) in automated agent subshells.
- ❌ **NEVER** run PowerShell without `-NoProfile -NonInteractive -ExecutionPolicy Bypass` in agent commands. Profile loading introduces latency, telemetry delays, and potential subshell hangs.
- ❌ **NEVER** pass unescaped variables inside double-quoted `powershell.exe -Command "..."` strings from pwsh. Always wrap in single quotes `'...'` or use `.ps1` script files.
- ❌ **NEVER** run `uv tool install --force` while target tool binaries (such as `graphify-mcp.exe`) are actively held open by live MCP servers.
- ❌ **NEVER** end a turn without presenting the tool results and answering the user's intent.


---

## 🛡 4. Non-Interactive Execution Best Practices

1. **Environment Variables**:
   The system has configured:
   - `PAGER=cat`
   - `BAT_PAGER=""`
   - `BAT_STYLE=plain`
   - `GIT_PAGER=cat`
   - `DELTA_PAGER=cat`
   - `PYTHONUTF8=1`
   Even with these environment variables, it is best practice to pass `--paging=never` and `--no-pager` when calling CLI tools to guarantee non-interactive completion.

2. **Cross-Platform Path Separators**:
   - Modern Rust/Go CLI utilities (`rg`, `fd`, `sd`, `ast-grep`, `bat`, `jaq`, `jq`, `xh`, `difft`) fully support standard forward slashes `/` on Windows (e.g. `rg "fn main" src/main.rs`).
   - Use standard forward slashes `/` or double-quoted paths for paths containing spaces.

3. **Shell Independence & OS Purity**:
   - Keep command lines strictly Windows-native (PowerShell 7 / Nushell / compiled native `.exe`).
   - Do not invoke or deliberate over Linux/macOS bash scripts when inspecting cross-platform configurations.

4. **PowerShell (.ps1) Scripts & UTF-8 with BOM**:
   - Legacy Windows PowerShell 5.1 (`powershell.exe`) defaults to Shift-JIS (CP932) for BOM-less files. Any `.ps1` script containing non-ASCII / Japanese / CJK characters **MUST be saved as UTF-8 with BOM (`utf-8-sig`)** to prevent parser crashes (e.g. `TerminatorExpectedAtEndOfString`).
   - Standard code/data files (Rust, JS/TS, Python, JSON, YAML, Markdown) remain UTF-8 without BOM.
   - When creating or editing `.ps1` scripts with Japanese text, ensure BOM is preserved and verify AST parsing via `just test`.

5. **Transparent User Environment & API Key Bridge**:
   - When running CLI tools that depend on external API keys (`OPENAI_API_KEY`, `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_BASE_URL`), automatically query and bridge Windows User Registry keys (`[Environment]::GetEnvironmentVariables('User')`) into the process table before execution if not already present in the current subshell snapshot.


---

## 📊 5. Terminal Diagram & Mermaid Output Policy (Cognitive Load Reduction)

1. **Terminal-Friendly Direct Diagrams**:
   - When presenting architecture, data flows, or state machines in terminal conversational responses, **prefer clean Unicode Box Drawing diagrams (`┌─┐`, `│`, `──►`) directly in the response** to minimize user cognitive load.
   - Always enclose Unicode diagrams in standard plaintext code blocks (` ```text `) to prevent UI syntax highlighters from misinterpreting characters as syntax errors or displaying invalid colors.
   - **East Asian Width (2:1) Rule**: When including Japanese (full-width / CJK) characters in Unicode box diagrams, strictly treat full-width characters as **width 2** and half-width characters as **width 1** so that box borders (`│`, `┌─┐`) align perfectly without horizontal displacement.
   - For simple flows (3–5 nodes), inline Unicode art provides instant comprehension without requiring external tools.

2. **Standardized Mermaid Code Blocks**:
   - When Mermaid syntax is used, always enclose it in standard fenced code blocks (` ```mermaid `) so the user's terminal renderer (`mm` in Nushell) can automatically detect and render it.
   - For complex architectures, ER diagrams, or detailed sequence flows, write the full diagram to a markdown artifact or documentation file where rich graphical rendering is supported.

---

## ⚡ 6. Agent Execution, Investigation & Zero-Waste Protocol

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Ultra-Fast Agent Execution Protocol                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Ground Truth First: Run `just test` for instant verification             │
│ 2. Two-Tier Discovery: Graphify Topology (L0/L1) -> Scoped CLI (L2)         │
│ 3. Strict Read Budget: Max 2–3 `view_file` calls (No whole-file cascades)   │
│ 4. Safe Workspace Editing: Use `replace_file_content` (No ArtifactMetadata) │
│ 5. Atomic SSOT Edit: Edit configs/ master files -> run `just deploy/sync`   │
│ 6. Batch Completion: Run `graphify update .` once per edit batch            │
└─────────────────────────────────────────────────────────────────────────────┘
```

1. **Automated Ground Truth Validation (Test First for Audits & Surveys)**:
   - When asked to audit, check, or survey whether documentation/configurations match current reality, **ALWAYS run `just test` (or the project test suite) FIRST**.
   - A passing test suite provides immediate proof of system integrity across 80+ parameters in seconds, eliminating the need to manually read dozens of source files.

2. **Two-Tier Hybrid Discovery (Graphify Topology + Native CLI Granularity)**:
   - **Tier 1 (High-Level Topology via Graphify L0/L1)**: When surveying a codebase, documenting system architecture, updating `README.md` / `AGENTS.md`, or exploring multi-component flows, ALWAYS use Graphify first (`query_graph`, `god_nodes`, `graphify query`) if `graphify-out/graph.json` exists. This reveals modules, functions, caller/callee trees, and skills in 1-2 tool calls.
   - **Tier 2 (Granular Detail via Native CLI L2)**: Use `rg -n`, `sd`, or `ast-grep` ONLY within the scoped files discovered in Tier 1 to locate specific string literals, variable lists, or line anchors. NEVER read 4+ whole files sequentially with `view_file`.

3. **Strict 3-File Read Budget & Zero-Cascade Guarantee**:
   - Limit `view_file` calls to a maximum of **2–3 scoped files per task**.
   - NEVER issue cascading sequential `view_file` calls across multiple files. Combine Graphify topology + `rg -n` anchor lines + automated tests instead.

4. **Safe Workspace Editing Protocol (`replace_file_content` vs `write_to_file`)**:
   - For all workspace files, **ALWAYS use `replace_file_content`**.
   - `write_to_file` with `ArtifactMetadata` is strictly reserved for `<appDataDir>\brain\<conversation-id>/...` artifacts. Passing `ArtifactMetadata` to workspace project paths will cause a permission validation failure and agent rework.
   - For full-file replacement of workspace files, use `replace_file_content` targeting lines `1..N`.

5. **Fast Remote Repository Investigation**:
   - When given a GitHub URL (e.g. `https://github.com/owner/repo`):
     - **Inspect metadata/README**: Run `gh repo view owner/repo` (or fetch raw README via `https://raw.githubusercontent.com/owner/repo/HEAD/README.md`).
     - **Deep codebase inspection**: Clone shallowly to scratch space: `git clone --depth 1 https://github.com/owner/repo.git ./scratch/repo_inspect` and search locally via `fd` / `rg`. This is 10x faster and more reliable than multiple GitHub API calls.

6. **Eliminate Duplicate Reads (Context Reuse)**:
   - Do NOT issue `view_file` on a file you have already inspected in the conversation.
   - If exact line numbers are needed for `replace_file_content`, run a 1-line `rg -n "anchor"` command rather than loading the entire file again.

7. **Atomic Modification & SSOT-First Workflow**:
   - Combine multiple related edits in a single pass rather than making fragmented, repetitive tool calls to the same file.
   - Modify the single master source in `configs/` and immediately run `just deploy` or `just sync-rules` rather than manually editing mirrored target files.

8. **Always Use `-NoProfile` for PowerShell Invocations**:
   - When running PowerShell scripts or inline commands, always supply `-NoProfile -NonInteractive -ExecutionPolicy Bypass` (e.g. `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ...` or `pwsh -NoProfile ...`). This prevents module loading and telemetry delays that cause CLI timeouts.

9. **Synchronous Execution & Active Hang Recovery**:
   - For CLI commands expected to finish quickly (< 10 seconds), always allocate the full synchronous wait limit (`WaitMsBeforeAsync: 10000`).
   - If a background command unexpectedly hangs (e.g. network/API stall), immediately terminate it with `manage_task kill` and switch to a deterministic native alternative.

---

## 🤖 7. Autonomous Agent CLI Quick Reference

| Agent CLI | Command | Common Execution Flags |
| :--- | :--- | :--- |
| **Cursor Agent CLI** | `agent` / `cursor-agent` | `agent "prompt"` (Interactive session)<br>`agent -p "prompt"` (Script / Non-interactive print)<br>`agent --mode plan "prompt"` (Plan-only / Read-only)<br>`agent --yolo` / `agent -f` (Auto-execute without confirmations)<br>`agent login` (Browser OAuth login)<br>`agent models` (List available models) |
| **Claude Code** | `claude` | `claude` (Interactive session)<br>`claude -p "prompt"` (Non-interactive print) |
| **Antigravity CLI** | `agy` | `agy` (Interactive chat & workspace session) |

---

## 🧠 8. Graphify Hybrid Protocol (Gated & Task-Classified)

**Gate:** Use graphify only when `graphify-out/graph.json` exists, or the user asks to build a graph. Otherwise use `rg` / `fd` / `ast-grep` and do **not** call graphify, MCP graph tools, or `/graphify`.

### 📋 Task Classification & Trigger Protocol (When Gate Passes)

| Task Category | Examples | Trigger Rule | Execution Path |
| :--- | :--- | :--- | :--- |
| **A. System Survey & Global Overview** | README/AGENTS.md sync, architecture docs, codebase tour, dependency analysis, impact/blast radius | **Mandatory L0/L1 Trigger**<br>(Do NOT bypass just because a single doc file is named in prompt) | `query_graph` / `god_nodes` (or `graphify query` on error) → Scoped `rg -n` → `replace_file_content` → `graphify update .` |
| **B. Multi-Component Feature / Refactor** | Adding a CLI command, modifying shared types, altering runtime pipeline | **Mandatory L0/L1 Trigger** | `get_node` / `shortest_path` (or `graphify path` on error) → Scoped `ast-grep` / `rg` → Edits → `graphify update .` |
| **C. Self-Contained Pinpoint Fix** | Typo fix on known line, isolated syntax bug, static color hex change | **Bypass L0/L1** (Direct to L2) | `rg -n` anchor → `replace_file_content` → `graphify update .` (if batch modified code) |

### 🪜 The Graphify Execution Ladder & Immediate Fallback

```text
L0  MCP   query_graph / get_node / get_neighbors / shortest_path  (try first if MCP tools exist)
          │
          └── [On ANY error / failure / tool absent] ──► IMMEDIATELY fall back to L1:
L1  CLI   graphify query "<topic>" --budget 1500  /  graphify god-nodes --top 10
L2  Locate rg -n / fd / ast-grep                                   (scoped paths ONLY)
L3  Edit  replace_file_content / sd / ast-grep -U                (atomic surgical edits)
L4  Sync  graphify update .                                       (once per edit batch; AST-only)
```

- **Turn / Batch Completion Checklist**:
  1. Complete code/documentation edits via `replace_file_content` / `sd`.
  2. If `graphify-out/graph.json` exists in repo, run `graphify update .` **once at the end of the batch**.
  3. Verify test suite & rule synchronization (`just test` / `just check-rules`).
  4. Present structured results to the user. Never end turn silently.



