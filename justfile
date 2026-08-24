# =============================================================================
#  dotfiles-windows - Just Command Runner
# =============================================================================

set windows-shell := ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]

# Default task: list all available commands
default:
    @just --list

# Sync AI Agent SSOT rules and skills from configs/agents/ to workspace and global configs
sync-rules:
    @powershell -ExecutionPolicy Bypass -File ./scripts/sync_agent_rules.ps1

# Check if all AI Agent rules and skills are in sync with the master SSOT files
check-rules:
    @powershell -ExecutionPolicy Bypass -File ./scripts/sync_agent_rules.ps1 -Check

# Deploy all dotfile configurations (Windows Terminal, Helix, Nushell, Profiles, etc.)
deploy:
    @powershell -ExecutionPolicy Bypass -File ./scripts/04_setup_configs.ps1

# Run the comprehensive test suite to verify CLI tools, environment variables, and rules
test:
    @powershell -ExecutionPolicy Bypass -File ./tests/verify_tools.ps1

# Run the full setup process (Winget, Fonts, Runtimes, Configs)
install:
    @powershell -ExecutionPolicy Bypass -File ./install.ps1 -All
