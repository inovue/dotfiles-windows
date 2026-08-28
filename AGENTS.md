# dotfiles-windows — Agent Guide

Windows dotfiles with deterministic deployment. This file is a router: project facts, commands, and pointers.
Global behavior rules (tool matrix, graph-first protocol, read budget) are deployed globally from `configs/agents/GLOBAL_RULES.md` — they are not restated here.

## Project Invariants

- **SSOT**: every master config lives in `configs/`. Never edit deployed copies (`$env:APPDATA`, `~/.cursor`) — edit `configs/` then run `just deploy` (app configs) or `just sync-rules` (Cursor rules & skills only).
- **Generated mirrors**: extra always-on files at repo root (for example `.cursorrules`) are intentionally absent. Cursor reads `AGENTS.md` natively; extra mirrors double-load every turn.
- **PowerShell**: After install, recipes invoke `pwsh.exe -NoProfile -ExecutionPolicy Bypass` (PowerShell 7). `just`'s windows-shell and `just install` stay `powershell.exe` so a new machine can bootstrap before winget installs pwsh. Run standalone `.ps1` with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. Any `.ps1` containing CJK must be UTF-8 with BOM. Do not wrap agent commands in `powershell.exe` (Windows PowerShell 5.1).
- **Graph present**: `graphify-out/graph.json` exists — graph-first navigation applies (survey: `just hubs` then neighbors/affected; modify: checkpoint if ≥3 files/security → `just path` → scoped `rg -n` → deploy/`just update-graph`). `just audit` is the Done contract, not a survey. Git hooks (post-commit/post-checkout/merge-driver via `graphify hook install`) auto-rebuild the graph.
- **Graphify engine only, rules SSOT**: never run `graphify … install` vendor rule/hook installers — they would double-fire against `agent_guard.py`. Engine CLI/MCP/git hooks are used; rules/skills stay masters in `configs/agents/`.

## Map

```text
configs/           SSOT for all configs
  agents/          GLOBAL_RULES.md, GUARD_POLICY.md, HARNESS_BASELINE.md, cursor/, skills/
  helix/ herdr/ lazygit/ nushell/ powershell/ starship/ windows-terminal/ rtk/ cursor/
scripts/           01_winget_packages.ps1, 02_install_fonts.ps1, 03_setup_runtimes.ps1, 04_setup_configs.ps1, Assert-PinnedHash.ps1, agent_guard.py, audit_workspace.ps1, graphify_semantic.py, merge_cursor_agent_shell.py, report_session_log.py, setup_api_keys.ps1, sync_agent_rules.ps1
tests/             verify_tools.ps1, verify_security.ps1, verify_agent_guard.ps1, verify_semantic_harness.ps1
graphify-out/      knowledge graph artifacts (graph.json, graph.html, report)
install.ps1        master installer (-All / -Step N / -UseSymlinks)
justfile           task runner — all common operations
```

## Commands (always prefer `just` over hand-built shell)

| Command | Purpose |
| :--- | :--- |
| `just audit` | 4-phase ground-truth audit (tests + SSOT sync + graph health + junk scan). Done contract / regression — not the first survey step. |
| `just test` | environment suite + security regression + agent_guard v5 |
| `just deploy` | deploy `configs/` to user & app directories |
| `just sync-rules` / `just check-rules` | propagate (or verify) agent rules & skills |
| `just graph "<q>"` / `just hubs` / `just neighbors <l>` / `just path <a> <b>` / `just affected <n>` | knowledge-graph queries |
| `just diagnose` / `just graph-tree` / `just graph-bench` / `just check-pins` | graph health / tree / token bench / version pins |
| `just update-graph` | refresh graph once per edit batch (AST `--force` + cached semantic rehydrate) |
| `just lessons` / `just remember "<q>" "<a>"` | work-memory loop: read lessons at session start / save Q&A as future graph nodes |
| `just check-semantic` / `just semantic-prepare` / `just semantic-merge` | pending docs flag / list uncached files / merge agent JSON (skill `graphify-builder`; no `graphify extract`) |
| `just watch` | background AST freshness (`graphify watch .`; no auto-LLM) |
| `just update-graphify` | upgrade graphify engine + refresh hooks + sync + test |
| `just session-report` | session-log deny rate, thrash, crawl (cumulative slices), poll_guide |
| `just install-graph-hook` | install post-commit auto-rebuild hook (once per clone) |
| `just checkpoint` / `just rollback` | git safety net around risky edits |
| `just clean` | remove temp / backup junk |
| `just install` / `just setup-keys` | full machine setup / API key configuration |
| `just setup-harness` / `just check-harness` | fix or verify Cursor × Windows harness baseline (env, PATH, settings) |

## Deeper Docs (load on demand, do not inline)

| Topic | Location |
| :--- | :--- |
| Human setup guide | `README.md` |
| Global agent rules master | `configs/agents/GLOBAL_RULES.md` |
| Guard gate table | `configs/agents/GUARD_POLICY.md` |
| Graphify tool schemas & protocol | skill `graphify-navigator` |
| Semantic graph (docs/images INFERRED) | skill `graphify-builder` |
| Modern CLI recipes | skill `modern-cli-expert` |
| Token proxy usage | skill `rtk-expert` |
| Harness baseline & session strategy (2026-08-28) | `docs/session-2026-08-28-harness-strategy.md` |
