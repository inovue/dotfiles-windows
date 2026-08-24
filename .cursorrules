# AI Agent Operational Rules & Modern Tooling Guide (SSOT)

> **Single Source of Truth (SSOT)**: This document defines mandatory guidelines, performance rules, and CLI conventions for all autonomous coding agents (Antigravity CLI, Cursor Agent, Claude Code, Codex CLI, etc.) operating in this workspace and across this Windows environment.

---

## ⚡ 1. Core Directives & Performance Principles

1. **Extreme Speed & Low Latency First**:
   - Always prefer **compiled, native Rust/Go CLI utilities** (`rg`, `fd`, `sd`, `ast-grep`, `bat`, `jaq`/`jq`, `xh`, `procs`, `difft`, `uutils-coreutils`) over slow, interpreted commands or heavy PowerShell cmdlets.
   - Streaming raw byte streams is 10x to 100x faster and consumes a fraction of the memory compared to PowerShell .NET object pipelines.

2. **Non-Interactive & Zero-Hang Guarantee**:
   - Never allow commands to invoke interactive pagers (`less`, `more`, interactive `bat`, interactive `git diff`).
   - Always supply non-interactive / bypass flags (`--paging=never`, `--no-pager`, `-y`, `--yes`, `--force`) when executing terminal tools.

3. **Deterministic UTF-8 Text Processing**:
   - Assume all code and text files are UTF-8. Avoid tools that output legacy Windows codepages (Shift-JIS/CP932) or add unexpected UTF-16 BOMs.

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

## 🚫 3. Prohibited Commands & Anti-Patterns

- ❌ **NEVER** pipe `Get-Content` into `Select-String` (e.g. `Get-Content file.txt | Select-String "foo"`). This loads the entire file into .NET objects in memory. Always use `rg "foo" file.txt`.
- ❌ **NEVER** use `Get-ChildItem -Recurse -Filter *.ext`. Always use `fd -e ext`.
- ❌ **NEVER** run commands that wait for user confirmation without an automatic yes flag (e.g., use `winget install --silent --accept-package-agreements`, `npm init -y`, `rm -Force`).
- ❌ **NEVER** leave pagers enabled on `git diff` or `git log`. Always use `git --no-pager diff` or set `GIT_PAGER=cat`.
- ❌ **NEVER** use interactive editors (`vi`, `vim`, `nano`, `helix`) in automated agent subshells.

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

3. **Shell Independence**:
   - Keep command lines compatible across PowerShell, Git Bash, and Nushell by invoking native CLI binaries directly rather than relying on shell-specific internal scripting functions.

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
