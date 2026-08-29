# =============================================================================
#  dotfiles-windows - Just Command Runner
# =============================================================================

set windows-shell := ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]

# Default task: list all available commands
default:
    @just --list

# Sync AI Agent SSOT rules and skills from configs/agents/ to workspace and global configs
sync-rules:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/sync_agent_rules.ps1

# Check if all AI Agent rules and skills are in sync with the master SSOT files
check-rules:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/sync_agent_rules.ps1 -Check

# Deploy all dotfile configurations (Windows Terminal, Helix, Nushell, Profiles, etc.)
deploy:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/04_setup_configs.ps1

# Run the comprehensive test suite (CLI tools, env, security)
test:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_tools.ps1
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_security.ps1
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_browser_agent.ps1

# Manual SSO smoke (skipped unless BROWSER_AGENT_SSO_TEST=1)
test-browser-sso:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_browser_agent_sso.ps1

# Force manual SSO smoke (requires ~/.chrome-profiles/work + network)
test-browser-sso-run:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_browser_agent_sso.ps1 -Run

# Run the 3-phase unified workspace audit (Tests, SSOT sync, Junk scan)
audit:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/audit_workspace.ps1

# Clean temporary files, stale backups (*.bak), and cache artifacts
clean:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/audit_workspace.ps1 -Clean

# Run the full setup process (Winget, Fonts, Runtimes, Configs)
install:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./install.ps1 -All

# Securely configure AI Agent API keys in Windows User Environment
setup-keys:
    @pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/setup_api_keys.ps1

# Securely configure fal.ai API key (FAL_KEY) for LP asset generator & background removal
setup-fal:
    @pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/setup_api_keys.ps1 -FalOnly

# Create a lightweight git checkpoint branch before risky agent edits
checkpoint:
    @$tag = 'checkpoint-' + (Get-Date -Format 'yyyyMMdd-HHmmss'); git branch $tag; Write-Host "[OK] Created git checkpoint branch: $tag" -ForegroundColor Green

# Rollback to the most recent git checkpoint branch
rollback:
    @$latest = (git branch --list 'checkpoint-*' | ForEach-Object { $_.Trim().TrimStart('* ') } | Sort-Object -Descending | Select-Object -First 1); if ($latest) { git reset --hard $latest; Write-Host "[OK] Rolled back to latest checkpoint: $latest" -ForegroundColor Green } else { Write-Warning 'No checkpoint branches found to rollback to.' }

# Compare installed rtk against configs/pins.json
check-pins:
    @$p = Get-Content configs/pins.json -Raw | ConvertFrom-Json; $r = rtk --version 2>&1 | Out-String; if ($r -notmatch [regex]::Escape($p.rtk)) { throw "rtk pin mismatch: $r expected $($p.rtk)" }; Write-Host "[OK] pins rtk=$($p.rtk)"

# Summarize session-log.jsonl deny rate, thrash, crawl, poll_guide
session-report:
    @python scripts/report_session_log.py

# Show RTK LLM token reduction analytics dashboard
rtk-gain:
    @rtk gain

# Show RTK recent command execution history with savings breakdown
rtk-history:
    @rtk gain --history

# Discover missed token-saving opportunities from agent history
rtk-discover:
    @rtk discover

# Update RTK to the pinned release (configs/pins.json), re-sync agent rules, and verify
update-rtk:
    @pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/03_setup_runtimes.ps1 -OnlyRtk -Force
    @just sync-rules
    @just test
