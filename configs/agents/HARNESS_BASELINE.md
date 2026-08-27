# Harness Baseline (Cursor × Windows)

> **Agents: treat everything below as already applied.** Do not reconfigure shell, Cursor
> `settings.json`, Windows user PATH, or hooks unless the user explicitly asks.
> Provisioned by `just install` / `just deploy` + `just sync-rules` (or `just setup-harness`).

## Fixed at setup

| Layer | What is locked | SSOT |
| :--- | :--- | :--- |
| Agent Shell | `pwsh.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass` | `configs/cursor/harness-settings.json` → `%APPDATA%/Cursor/User/settings.json` |
| Terminal encoding | UTF-8 (`files.encoding`, `PYTHONUTF8=1`) | same |
| User PATH | `~/.local/bin` prepended (rg, fd, rtk, graphify, …) | `scripts/setup_cursor_harness.ps1` |
| User env | `GIT_PAGER=cat`, telemetry off, `DOTFILES_HARNESS=cursor-windows-v1` | same + automationProfile `env` |
| Hooks | `agent_guard.py` v4.7 PreToolUse / beforeMCP / stop | `configs/agents/cursor/hooks.json` |
| Rules | `AGENTS.md`, `graphify.mdc`, skills | `configs/agents/` → `just sync-rules` |
| MCP | graphify workspace-local pin; global unpinned | `sync_agent_rules.ps1` MCP merge |
| PowerShell policy | `RemoteSigned` CurrentUser | `04_setup_configs.ps1` step 4.3 |

## Agent invariants (harness assumes)

- **Shell tool** runs in automationProfile above — `&&` / `||` work; never wrap in `powershell.exe` (5.1).
- **Hooks enforce** graph-gate, read budget, rtk, destructive deny — see `GLOBAL_RULES.md` §Guarantees live in hooks.
- **Finite jobs** use `block_until_ms >= 120000` in Shell (Cursor); never poll short waits.
- **Out-of-repo writes** (`~/.cursor/plans`, etc.) are allowed; in-repo edits need graph contact when `graphify-out/graph.json` exists.

## Verify / repair

```powershell
just setup-harness   # re-apply env, PATH, Cursor settings, baseline manifest
just check-rules     # SSOT drift only
just audit           # full harness health (includes automationProfile check)
```

Baseline manifest (written on setup): `~/.cursor/harness-baseline.json`

## Session report

Full strategy, bloat analysis, and unimplemented roadmap: `docs/session-2026-08-28-harness-strategy.md`
