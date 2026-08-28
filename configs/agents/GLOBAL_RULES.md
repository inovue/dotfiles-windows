# Global AI Agent Rules (SSOT Master)

> Cursor-only always-on rules on this Windows machine. Procedures live in skills — load one instead of guessing:
> `modern-cli-expert`.
> Pins: `configs/pins.json`.

## Core Invariants

- **SSOT**: edit `configs/agents/`, then `just sync-rules` (Cursor targets only). Deployed mirrors are generated.
- **PowerShell 7**: after install, `just` recipes use `pwsh`. `just install` stays `powershell.exe` for bootstrap. CJK `.ps1` must be UTF-8 with BOM.
- **Non-interactive**: `--paging=never`, `--no-pager`, `-y`; run `.ps1` with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
- **Native CLI first**: `rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft` — not PowerShell pipelines (`Select-String`, `Get-ChildItem -Recurse`).
- **Finish with structure**: concise markdown, never bare tool output.
- **Done contract**: a "fix" needs a fail→pass check in the same batch. `just audit` PASS proves no regression, not that the fix works.
- **Independent review**: multi-file or security batches need a fresh-context reviewer on the diff + Done contract.

## Tool Quick Map

| Task | Command |
| :--- | :--- |
| Content search | `rg -n "pat" <path>` |
| File search | `fd "pat" -t f` |
| View | Read (native) |
| Replace / AST | `sd` / `ast-grep` |
| JSON / HTTP | `jaq` / `xh` |
