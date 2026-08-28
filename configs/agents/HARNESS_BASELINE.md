# Harness Baseline (Cursor × Windows v2)

> **Agents: treat everything below as already applied.** Do not reconfigure shell, Cursor
> `settings.json`, Windows user PATH, or hooks unless the user explicitly asks.
> Provisioned by `just install` / `just setup-harness`. Pins: `configs/pins.json`.

## Fixed at setup

| Layer | What is locked | SSOT |
| :--- | :--- | :--- |
| Harness id | `cursor-windows-v2` | `configs/pins.json` |
| Agent Shell | `pwsh.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass` | `configs/cursor/harness-settings.json` |
| graphifyy / rtk | `0.9.50` / `0.45.0` | pins + `03_setup_runtimes.ps1` |
| PATH | `~/.local/bin` prepended | `scripts/setup_cursor_harness.ps1` |
| Env | UTF-8, pagers off, telemetry off, `RTK_TELEMETRY_DISABLED=1` | harness-settings |
| Hooks | v5.1 project graph-first + user destructive Shell-only (no dual full guard). stop `loop_limit` 5 | `configs/agents/cursor/hooks.json` + `hooks.global.json` |
| Rules / skills | Cursor-only sync | `just sync-rules` |
| MCP | workspace pin; global unpinned | sync-rules MCP merge |

## Agent invariants

- Shell is pwsh 7 — never wrap in `powershell.exe` (5.1).
- Hooks rewrite noisy shell via `rtk rewrite` (`updated_input`). Graph-gate, read budget, hard-loop: `GUARD_POLICY.md`.
- Finite jobs: `block_until_ms >= 120000`. Never poll.
- Out-of-repo writes are allowed; in-repo edits need graph contact when `graphify-out/graph.json` exists.
- Stop will follow up until `just update-graph` (+ semantic-merge if docs) when a graph exists. `just audit` is the Done contract, not a stop loop.

## Verify / repair

```powershell
just setup-harness   # re-apply env, PATH, Cursor settings, baseline manifest
just check-pins      # graphify / rtk / harness id vs configs/pins.json
just check-rules     # SSOT drift (Cursor targets)
just audit           # full harness health
```

Baseline manifest: `~/.cursor/harness-baseline.json`

Strategy: `docs/session-2026-08-28-harness-strategy.md`
