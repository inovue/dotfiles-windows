---
name: rtk-expert
description: >-
  High-speed LLM token optimizer & CLI proxy (rtk). Cuts 60-90% of bash/shell output tokens.
  Use when running git commands, viewing/reading files (rtk read), heuristic summarization
  (rtk smart), test execution (rtk test), diffing (rtk diff), linting, directory discovery,
  piping stdin (rtk pipe), tracking savings (rtk gain), or rewriting raw commands (rtk rewrite).
---

# RTK Token Optimizer Expert (rtk-expert)

> **Core Purpose**: `rtk` (Rust Token Killer) is a high-performance, single-binary CLI proxy that intercepts dev commands and filters out noise, whitespace, boilerplate, and duplicate logs before LLM context ingestion.

> **This harness**: `agent_guard` PreToolUse calls `rtk rewrite` and returns Cursor `updated_input`. Still write `rtk …` explicitly when you can; raw `git status` is rewritten to `rtk git status`. Built-in **Read/Grep are preferred** for ordinary files. For files over the 300-line cap use `rtk read` / `rtk rg`. `--ultra-compact` is optional, not default.

---

## ⚡ 1. Token-Slashing Command Matrix

| Intent / Operation | ❌ Raw Verbose Command | ⚡ Ultra-Compact RTK Command | Typical Savings |
| :--- | :--- | :--- | :--- |
| **Git Status** | `git status` | `rtk git status` | ~70% (clean one-line status) |
| **Git Diff** | `git diff` | `rtk git diff` | ~65% (condensed changed lines) |
| **Git Log** | `git log -n 10` | `rtk git log -n 10` | ~80% (one-line commit graph) |
| **Git Actions** | `git add . && git commit` | `rtk git add .` / `rtk git commit -m "..."` | ~85% (compact `ok <sha>`) |
| **File Reading** | `cat file` / `bat file` | `rtk read [file]` or `rtk read -m <N> [file]` | ~70% (strips boilerplate/noise) |
| **Aggressive Read** | Sliced viewing | `rtk read [file] -l aggressive` | ~85% (signatures only) |
| **Code Summary** | Manual skimming | `rtk smart [file]` | ~95% (2-line structural summary) |
| **File Search** | `find . -name "*.rs"` | `rtk find "*.rs" [path]` | ~75% (compact tree output) |
| **Grep / Search** | `grep -rn "pattern" .` | `rtk grep "pattern" [path]` / `rtk rg "pattern"` | ~60% (grouped by file) |
| **Syntax Diff** | `diff file1 file2` | `rtk diff file1 file2` | ~80% (changed lines only) |
| **Cargo Test** | `cargo test` | `rtk cargo test` | ~90% (failures-only report) |
| **Python Test** | `pytest` / `uv run pytest` | `rtk pytest` / `rtk uv run pytest` | ~90% (failures only) |
| **Generic Test** | `npm test` / `vitest` / `jest` | `rtk test <command>` | ~90% (strips passed noise) |
| **Lint & Typecheck** | `eslint`, `tsc`, `ruff` | `rtk lint`, `rtk tsc`, `rtk ruff check` | ~80% (grouped error view) |
| **JSON Preview** | `cat data.json` | `rtk json data.json --keys-only` | ~85% (structural schema only) |
| **Package Deps** | `pnpm list`, `pip list` | `rtk deps` / `rtk pnpm list` | ~75% (compact dependency tree) |
| **Hook rewrite (SSOT)** | raw `git status` | `rtk rewrite "git status"` | harness auto via `updated_input` |
| **Stdin pipe** | `cmd \| more` | `cmd \| rtk pipe` | ~60% (filter stdin) |
| **Ultra-compact** | default rtk | `rtk --ultra-compact <cmd>` | extra; **not default** |
| **Savings dashboard** | — | `rtk gain` / `just rtk-gain` | session totals |

---

## 🛠 2. Practical High-Yield Recipes

### 1. Smart Pinpoint File Inspection
```bash
rtk smart scripts/agent_guard.py          # 2-line heuristic summary
rtk read src/main.rs                      # noise/blank lines stripped
rtk read -m 120 README.md                 # cap lines; do NOT use -n (that's --line-numbers)
rtk read src/service.ts -l aggressive     # signatures only
```

### 2. Failure-Only Test & Build Runs
```bash
rtk cargo test
rtk pytest
rtk test npm run test:unit
rtk tsc
```

### 3. Git Operations & Commits
```bash
rtk git status
rtk git diff
rtk git add -A
rtk git commit -m "feat: integrate rtk token killer"
```

### 4. Rewrite, pipe, gain
```bash
rtk rewrite "git status"          # SSOT for hooks; prints `rtk git status` (exit 1 = no mapping)
git diff | rtk pipe               # filter stdin
rtk gain                          # dashboard; or `just rtk-gain`
rtk gain --history
rtk --ultra-compact git status    # optional Level-2; not default
```

### 5. Zero Re-Run Failure Recovery (Tee Log)
When a test or build fails, RTK caches the full uncompressed log to `~/.local/share/rtk/tee/` or `%LOCALAPPDATA%\rtk\tee\`:
```text
FAILED: 2/15 tests [full output: ~/.local/share/rtk/tee/1707753600_cargo_test.log]
```
> **Tip**: Do not re-run with `--verbose`. Inspect the saved log with `rtk log <log_path>` (or `rtk read -m 30 <log_path>`).

---

## 🛡️ 3. Invariants & Rules
1. **Prefer explicit `rtk …`**: write it yourself when you can. The harness still rewrites noisy shell via `rtk rewrite` (`updated_input`) if you forget.
2. **Read/Grep are native first**: built-in Read/Grep do not hit rtk rewrite. For files over 300 lines use `rtk read` / `rtk rg`.
3. **`--ultra-compact` is opt-in**, not default. Use only when the extra ASCII/inline squeeze is needed.
4. **Telemetry Disabled**: `RTK_TELEMETRY_DISABLED=1` is globally enforced.
