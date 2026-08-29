# dotfiles-windows — Agent Guide

Windows dotfiles with deterministic deployment. This file is a router: project facts, commands, and pointers.
Global behavior rules are deployed globally from `configs/agents/GLOBAL_RULES.md` — they are not restated here.

## Project Invariants

- **SSOT**: every master config lives in `configs/`. Never edit deployed copies (`$env:APPDATA`, `~/.cursor`) — edit `configs/` then run `just deploy` (app configs) or `just sync-rules` (Cursor rules & skills only).
- **Generated mirrors**: extra always-on files at repo root (for example `.cursorrules`) are intentionally absent. Cursor reads `AGENTS.md` natively; extra mirrors double-load every turn.
- **PowerShell**: After install, recipes invoke `pwsh.exe -NoProfile -ExecutionPolicy Bypass` (PowerShell 7). `just`'s windows-shell and `just install` stay `powershell.exe` so a new machine can bootstrap before winget installs pwsh. Run standalone `.ps1` with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`. Any `.ps1` containing CJK must be UTF-8 with BOM. Do not wrap agent commands in `powershell.exe` (Windows PowerShell 5.1).
- **Done contract**: a "fix" needs a fail→pass check in the same batch. `just audit` proves no regression, not that the fix works. Checkpoint first if ≥3 files or security-sensitive.
- **rtk**: binary is pinned in `configs/pins.json` and installed by `03_setup_runtimes.ps1`. Cursor Shell rewrite is the official user hook (`rtk init -g --agent cursor --hook-only`). This repo does not own `~/.cursor/hooks.json`.

## Map

```text
configs/           SSOT for all configs
  agents/          GLOBAL_RULES.md, cursor/, skills/
  helix/ herdr/ lazygit/ nushell/ powershell/ starship/ windows-terminal/ rtk/
scripts/           01_winget_packages.ps1, 02_install_fonts.ps1, 03_setup_runtimes.ps1, 04_setup_configs.ps1, Assert-PinnedHash.ps1, audit_workspace.ps1, report_session_log.py, setup_api_keys.ps1, sync_agent_rules.ps1
tests/             verify_tools.ps1, verify_security.ps1, verify_browser_agent.ps1, verify_ascii_chat_diagrams.ps1
install.ps1        master installer (-All / -Step N / -UseSymlinks)
justfile           task runner — all common operations
```

## Commands (always prefer `just` over hand-built shell)

| Command | Purpose |
| :--- | :--- |
| `just audit` | 3-phase ground-truth audit (tests + SSOT sync + junk scan). Done contract / regression. |
| `just test` | environment suite + security regression + browser-agent smoke (108) |
| `just test-browser-sso` / `just test-browser-sso-run` | optional manual SSO capture (skipped in CI; requires `work` profile) |
| `just deploy` | deploy `configs/` to user & app directories |
| `just sync-rules` / `just check-rules` | propagate (or verify) agent rules & skills |
| `just check-pins` | rtk version vs `configs/pins.json` |
| `just session-report` | session-log summary |
| `just checkpoint` / `just rollback` | git safety net around risky edits |
| `just clean` | remove temp / backup junk |
| `just install` / `just setup-keys` | full machine setup / API key configuration |
| `just rtk-gain` / `just update-rtk` | rtk savings dashboard / reinstall pinned rtk + official Cursor hook |

## Deeper Docs (load on demand, do not inline)

| Topic | Location |
| :--- | :--- |
| Human setup guide | `README.md` |
| Global agent rules master | `configs/agents/GLOBAL_RULES.md` |
| Modern CLI recipes | skill `modern-cli-expert` |
| Browser automation (dev capture + SSO assist) | skill `browser-agent` |
| ASCII chat diagrams (wireframes, charts, flows) | skill `ascii-chat-diagrams` |
| Cursor × rtk strategy | `docs/session-2026-08-28-harness-strategy.md` |
