---
name: rtk-expert
description: >-
  High-speed LLM token optimizer & CLI proxy (rtk). Cuts 60-90% of bash/shell output tokens.
  Use when running git commands, viewing/reading files (rtk read), heuristic summarization
  (rtk smart), test execution (rtk test), diffing (rtk diff), linting, directory discovery,
  and tracking token savings (rtk gain).
---

# RTK Token Optimizer Expert (rtk-expert)

> **Core Purpose**: `rtk` (Rust Token Killer) is a high-performance, single-binary CLI proxy that intercepts dev commands and filters out noise, whitespace, boilerplate, and duplicate logs before LLM context ingestion.

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

---

## 🛠 2. Practical High-Yield Recipes

### 1. Smart Pinpoint File Inspection
```bash
# Get an instant 2-line technical heuristic summary (0 token overhead)
rtk smart scripts/agent_guard.py

# Read file with noise and blank lines stripped
rtk read src/main.rs

# Cap output lines: `rtk read -m <N> <file>`. Do NOT use `-n` — that is
# `--line-numbers` (a flag); a following number is parsed as a filename.
rtk read -m 120 README.md

# Read TypeScript/Python signatures only (ideal for caller/callee context)
rtk read src/service.ts -l aggressive
```

### 2. Failure-Only Test & Build Runs
```bash
# Runs tests and filters out all passed test noise; outputs only failing assertions
rtk cargo test
rtk pytest
rtk test npm run test:unit

# TypeScript type checking grouped by file
rtk tsc
```

### 3. Git Operations & Commits
```bash
# Clean status
rtk git status

# View compact diff before staging
rtk git diff

# Stage and commit with instant confirmation
rtk git add -A
rtk git commit -m "feat: integrate rtk token killer"
```

### 4. Zero Re-Run Failure Recovery (Tee Log)
When a test or build fails, RTK automatically caches the full uncompressed log to `~/.local/share/rtk/tee/` or `%LOCALAPPDATA%\rtk\tee\`:
```text
FAILED: 2/15 tests [full output: ~/.local/share/rtk/tee/1707753600_cargo_test.log]
```
> **Tip**: Agents never need to re-run commands with `--verbose`. Simply inspect the saved failure log using `head -n 30 <log_path>` or `rtk log <log_path>`.

---

## 📊 3. Token Analytics & Gain Tracking

Monitor token savings and optimization efficiency:
```bash
# View overall savings summary dashboard
rtk gain

# View recent command execution history with byte/token savings
rtk gain --history

# Discover missed token-saving opportunities from past sessions
rtk discover
```

---

## 🛡️ 4. Invariants & Rules
1. **Always Prefer RTK Over Raw Shell Commands**: For all standard dev commands (`git`, `cargo`, `pytest`, `npm`, `tsc`, `lint`), prepend `rtk` (or rely on the auto-rewrite hook).
2. **Combine with Agent Guard**: Agent Guard enforces safety and read budgets, while RTK ensures every shell output is compressed to minimal tokens.
3. **Telemetry Disabled**: `RTK_TELEMETRY_DISABLED=1` is globally enforced for complete privacy and instant execution.
