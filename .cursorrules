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
     - Run `just test` or `just audit` to verify complete environment and configuration integrity.
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
│   ├── audit_workspace.ps1    # 4-phase unified workspace audit (Tests, SSOT, Graph, Junk)
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
| `just audit` | 🌟 Run 4-phase unified audit (Tests + SSOT sync + Graph health + Junk scan) | First step for any survey/audit |
| `just test` | Run full automated test suite (CLI binaries, env vars, rules sync, UTF-8, benchmarks) | Before & after making changes |
| `just clean` | Clean up temporary files, stale backups (*.bak), and cache artifacts | After completing edits or before committing |
| `just deploy` | Deploy all `configs/` to user profile directories and Windows Terminal | After updating any file in `configs/` |
| `just sync-rules` | Synchronize AI rules and skills to global paths & project mirrors | After editing `configs/agents/` |
| `just check-rules`| Check if deployed rules match master SSOT without modifying files | During CI or pre-flight verification |
| `just checkpoint` | Create a lightweight git checkpoint branch before risky agent edits | Before large/destructive refactoring |
| `just rollback` | Instantly rollback to the most recent git checkpoint branch | After failed or broken agent edits |
| `just graph <q>`| 🧠 Fast compact query on knowledge graph (e.g. `just graph "deploy"`) | Architectural / symbol discovery |
| `just hubs` | Inspect top architectural hubs / god-nodes in codebase | High-level system overview |
| `just neighbors <l>`| Expand relations & child components of a specific hub or file | Hub exploration & blast radius |
| `just path <a> <b>` | Trace shortest caller/dependency path between two symbols | Dependency & refactor impact |
| `just update-graph`| Refresh repository knowledge graph via fast AST analysis | After completing an edit batch |
| `just install` | Run full clean setup (Packages, Fonts, Runtimes, Configs) | On fresh machine installation |
| `just setup-keys` | Securely configure AI Agent & Graphify API keys in Windows User Environment | When adding or updating API keys |

---

## 🛡️ 4. Project Operational Invariants

1. **PowerShell Non-Interactive Flags**:
   - In `justfile`, `set windows-shell := ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]` is configured.
   - When executing external `.ps1` directly, always provide `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
2. **Safe Workspace File Modification**:
   - Always use `replace_file_content` for modifying workspace files. Never pass `ArtifactMetadata` to workspace files.
3. **UTF-8 & PowerShell (.ps1) Encoding**:
   - Any `.ps1` script containing non-ASCII / Japanese / CJK characters **MUST be saved as UTF-8 with BOM (`utf-8-sig`)** to prevent Windows PowerShell 5.1 parser crashes.
4. **Graphify Fast Navigation in this Workspace**:
   - `graphify-out/graph.json` is present. Follow the 2-Tier Discovery protocol:
     - **Survey / Architecture**: Run `just audit` first → `god_nodes` / `get_neighbors` (expand hubs) → scoped `rg -n` / `replace_file_content`.
     - **Batch Sync**: Execute `just update-graph` once at the end of an edit batch.
