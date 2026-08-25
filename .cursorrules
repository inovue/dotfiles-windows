# AI Agent Workspace Guide for `dotfiles-windows`

> **Project Context & Operational Map**: This document equips coding agents (Antigravity, Cursor, Claude Code, Codex) with instant context, directory maps, and modification rules to prevent context drift, unnecessary file traversal, and token waste.

---

## 🧭 1. Architectural Principles & Single Source of Truth (SSOT)

1. **All Master Configurations Live in `configs/`**:
   - **NEVER** edit deployed files directly in `$env:APPDATA`, `$env:LOCALAPPDATA`, `$HOME/.gemini/config`, or `$HOME/.claude/`.
   - Always modify the template/source files under `configs/` inside this repository.
2. **Deterministic Deployment via `just`**:
   - After modifying configurations in `configs/`:
     - Run `just deploy` to apply changes to user and application directories.
     - Run `just sync-rules` to propagate AI agent rules & skills.
     - Run `just test` to verify complete environment and configuration integrity.
3. **Zero-Guessing Directory Map**:
   - Consult the directory map below before searching files with `fd` or `rg` to save tokens.

---

## 🗺️ 2. Repository Quick Map (Token-Saving Structure)

```text
dotfiles-windows/
├── AGENTS.md                  # Project-level agent navigation & workflow guide (This file)
├── CLAUDE.md                  # Claude Code workspace navigation (Synced with AGENTS.md)
├── .cursorrules               # Cursor agent rules (Synced with SSOT)
├── justfile                   # Just task runner definitions
├── README.md                  # Human & Agent user documentation
├── install.ps1                # Master installer entrypoint (-All / -Step N / -UseSymlinks)
│
├── configs/                   # 🌟 SINGLE SOURCE OF TRUTH (SSOT) FOR ALL CONFIGS
│   ├── agents/                # AI Agent master rules & skills
│   │   ├── AGENTS.md          # Global AI agent rules (CLI replacement matrix, zero-hang rules)
│   │   ├── antigravity/       # Antigravity MCP + always-on graphify rules/workflows
│   │   ├── cursor/            # Cursor always-on rules (graphify.mdc; gated on graphify-out/)
│   │   └── skills/            # Progressive disclosure agent skills
│   │       ├── browser-agent/ # Real Chrome automation engine (a11y tree, stealth, profiles)
│   │       ├── graphify-navigator/ # Graphify×Antigravity hybrid (MCP + rg/fd/sd)
│   │       └── modern-cli-expert/ # AST refactoring (ast-grep), sd, jaq, xh recipes
│   ├── helix/                 # Helix editor (config.toml, languages.toml)
│   ├── herdr/                 # Herdr AI TUI multiplexer (config.toml + herdr-sidebar)
│   ├── lazygit/               # Lazygit TUI + Delta config (config.yml)
│   ├── nushell/               # Nushell (config.nu, env.nu)
│   ├── powershell/            # PowerShell 5.1 & 7 profile (Microsoft.PowerShell_profile.ps1)
│   ├── starship/              # Starship prompt (starship.toml)
│   └── windows-terminal/      # Windows Terminal template (settings.json)
│
├── scripts/                   # Modular automation & setup scripts
│   ├── 01_winget_packages.ps1 # Winget package bulk installation
│   ├── 02_install_fonts.ps1   # UDEV Gothic 35NF automatic download & font registry
│   ├── 03_setup_runtimes.ps1  # fnm, uv, rustup, jaq, env vars, ~/.local/bin shims
│   ├── 04_setup_configs.ps1   # Deploy configs/ to $APPDATA, profiles, and Windows Terminal
│   ├── setup_api_keys.ps1     # Secure standalone API key setup (Windows User Environment)
│   └── sync_agent_rules.ps1   # Fast sync configs/agents/ to Antigravity/Claude/Cursor globals
│
└── tests/
    └── verify_tools.ps1       # Comprehensive automated integration, UTF-8 & speed test suite
```

---

## ⚡ 3. Agent Command Matrix

Always use these `just` commands instead of constructing manual shell commands:

| Command | Purpose | When to Run |
| :--- | :--- | :--- |
| `just test` | Run full automated test suite (CLI binaries, env vars, rules sync, UTF-8, benchmarks) | Before & after making changes |
| `just deploy` | Deploy all `configs/` to user profile directories and Windows Terminal | After updating any file in `configs/` |
| `just sync-rules` | Synchronize AI rules and skills to global paths & project mirrors | After editing `configs/agents/` |
| `just check-rules`| Check if deployed rules match master SSOT without modifying files | During CI or pre-flight verification |
| `just install` | Run full clean setup (Packages, Fonts, Runtimes, Configs) | On fresh machine installation |
| `just setup-keys` | Securely configure AI Agent & Graphify API keys in Windows User Environment | When adding or updating API keys |


---

## 🛡️ 4. Execution & Safety Rules

1. **PowerShell Non-Interactive Flags**:
   - Always run PowerShell commands with `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
   - In `justfile`, `set windows-shell := ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]` is already configured.
2. **Compiled Modern Tools Over PowerShell Cmdlets**:
   - `rg -n "term"` instead of `Select-String`
   - `fd -t f "pattern"` instead of `Get-ChildItem -Recurse`
   - `sd 'find' 'replace' file` instead of `sed` or string replacement scripts
   - `jaq` or `jq` instead of `ConvertFrom-Json`
3. **UTF-8 & PowerShell (.ps1) Encoding**:
   - Ensure all generated code, configs, and text files are saved in UTF-8.
   - **Critical for PowerShell (.ps1)**: Windows PowerShell 5.1 (`powershell.exe`) defaults to Shift-JIS/CP932 for BOM-less files. Any `.ps1` script containing non-ASCII / Japanese / CJK characters **MUST be saved as UTF-8 with BOM (`utf-8-sig`)** to prevent parser crashes (e.g. `TerminatorExpectedAtEndOfString`).
   - Never invoke interactive pagers or editors.

