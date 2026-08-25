# =============================================================================
#  dotfiles-windows - Just Command Runner
# =============================================================================

set windows-shell := ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]

# Default task: list all available commands
default:
    @just --list

# Sync AI Agent SSOT rules and skills from configs/agents/ to workspace and global configs
sync-rules:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/sync_agent_rules.ps1

# Check if all AI Agent rules and skills are in sync with the master SSOT files
check-rules:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/sync_agent_rules.ps1 -Check

# Deploy all dotfile configurations (Windows Terminal, Helix, Nushell, Profiles, etc.)
deploy:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/04_setup_configs.ps1

# Run the comprehensive test suite to verify CLI tools, environment variables, and rules
test:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_tools.ps1

# Run the 4-phase unified workspace audit (Tests, SSOT sync, Graph topology, Junk scan)
audit:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/audit_workspace.ps1

# Clean temporary files, stale backups (*.bak), and cache artifacts
clean:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/audit_workspace.ps1 -Clean

# Run the full setup process (Winget, Fonts, Runtimes, Configs)
install:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./install.ps1 -All

# Securely configure AI Agent & Graphify API keys in Windows User Environment
setup-keys:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/setup_api_keys.ps1

# Create a lightweight git checkpoint branch before risky agent edits
checkpoint:
    @$tag = 'checkpoint-' + (Get-Date -Format 'yyyyMMdd-HHmmss'); git branch $tag; Write-Host "[OK] Created git checkpoint branch: $tag" -ForegroundColor Green

# Rollback to the most recent git checkpoint branch
rollback:
    @$latest = (git branch --list 'checkpoint-*' | ForEach-Object { $_.Trim().TrimStart('* ') } | Sort-Object -Descending | Select-Object -First 1); if ($latest) { git reset --hard $latest; Write-Host "[OK] Rolled back to latest checkpoint: $latest" -ForegroundColor Green } else { Write-Warning 'No checkpoint branches found to rollback to.' }

# Refresh knowledge graph (AST code-only update)
update-graph:
    @graphify update .

# Query the knowledge graph with compact token budget (e.g. just graph "deploy")
graph query:
    @graphify query "{{query}}" --budget 1200

# Inspect the top architectural god-nodes and hubs in the codebase
hubs:
    @graphify god-nodes --top 5

# Expand neighbors and relationships of a specific component or hub
neighbors label:
    @graphify query "{{label}}" --budget 1200

# Trace the shortest dependency/caller path between two components
path source target:
    @graphify path "{{source}}" "{{target}}"

# Show RTK LLM token reduction analytics dashboard
rtk-gain:
    @rtk gain

# Show RTK recent command execution history with savings breakdown
rtk-history:
    @rtk gain --history

# Discover missed token-saving opportunities from agent history
rtk-discover:
    @rtk discover
