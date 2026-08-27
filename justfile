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

# Run the comprehensive test suite to verify CLI tools, environment variables, and rules
test:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_tools.ps1
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_security.ps1
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_agent_guard.ps1
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./tests/verify_semantic_harness.ps1

# Run the 4-phase unified workspace audit (Tests, SSOT sync, Graph topology, Junk scan)
audit:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/audit_workspace.ps1

# Clean temporary files, stale backups (*.bak), and cache artifacts
clean:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/audit_workspace.ps1 -Clean

# Run the full setup process (Winget, Fonts, Runtimes, Configs)
install:
    @powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./install.ps1 -All

# Securely configure AI Agent & Graphify API keys in Windows User Environment
setup-keys:
    @pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/setup_api_keys.ps1

# Securely configure fal.ai API key (FAL_KEY) for LP asset generator & background removal
setup-fal:
    @pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/setup_api_keys.ps1 -FalOnly

# Re-apply Cursor × Windows harness baseline (env, PATH, settings.json, manifest)
setup-harness:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/setup_cursor_harness.ps1

# Verify harness baseline without applying changes
check-harness:
    @pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ./scripts/setup_cursor_harness.ps1 -Check

# Create a lightweight git checkpoint branch before risky agent edits
checkpoint:
    @$tag = 'checkpoint-' + (Get-Date -Format 'yyyyMMdd-HHmmss'); git branch $tag; Write-Host "[OK] Created git checkpoint branch: $tag" -ForegroundColor Green

# Rollback to the most recent git checkpoint branch
rollback:
    @$latest = (git branch --list 'checkpoint-*' | ForEach-Object { $_.Trim().TrimStart('* ') } | Sort-Object -Descending | Select-Object -First 1); if ($latest) { git reset --hard $latest; Write-Host "[OK] Rolled back to latest checkpoint: $latest" -ForegroundColor Green } else { Write-Warning 'No checkpoint branches found to rollback to.' }

# Refresh knowledge graph (AST code-only update), then rehydrate cached semantic
# nodes if any. --force is required: INFERRED nodes make an AST-only rebuild
# look like shrink, and the engine would otherwise refuse to write.
# Stamp graph.json mtime even when topology is unchanged.
update-graph:
    @graphify update . --force
    @uv tool run --from graphifyy python ./scripts/graphify_semantic.py rehydrate --force
    @if (Test-Path graphify-out/graph.json) { (Get-Item graphify-out/graph.json).LastWriteTime = Get-Date }

# Install post-commit git hook that auto-rebuilds the knowledge graph on every commit
install-graph-hook:
    @graphify hook install

# Query the knowledge graph with compact token budget (e.g. just graph "deploy")
graph query:
    @graphify query "{{query}}" --budget 1200

# Inspect the top architectural god-nodes and hubs in the codebase
hubs:
    @graphify god-nodes --top 5

# Expand neighbors and relationships of a specific component or hub
neighbors label:
    @graphify explain "{{label}}"

# Trace the shortest dependency/caller path between two components
path source target:
    @graphify path "{{source}}" "{{target}}"

# Session start: refresh lessons from work-memory (deterministic) and print them
lessons:
    @graphify reflect --if-stale
    @uv tool run --from graphifyy python ./scripts/graphify_semantic.py prepare
    @if (Test-Path graphify-out/reflections/LESSONS.md) { Get-Content graphify-out/reflections/LESSONS.md } else { Write-Host 'No lessons yet - save results with `just remember` to seed the loop.' -ForegroundColor DarkGray }

# Save a Q&A result to work-memory (becomes a graph node on next update)
remember question answer outcome="useful":
    @graphify save-result --question "{{question}}" --answer "{{answer}}" --type query --outcome {{outcome}}

# Check semantic freshness: engine needs_update flag AND SHA-uncached docs
check-semantic:
    @graphify check-update .
    @uv tool run --from graphifyy python ./scripts/graphify_semantic.py prepare --quiet-if-clean

# List uncached docs/images for skill graphify-builder (no LLM)
semantic-prepare:
    @uv tool run --from graphifyy python ./scripts/graphify_semantic.py prepare

# Merge agent-written .graphify_semantic.json + cache into graph.json (no LLM)
semantic-merge:
    @uv tool run --from graphifyy python ./scripts/graphify_semantic.py merge

# Watch the workspace: AST-only rebuilds on code changes (no LLM)
watch:
    @graphify watch . --debounce 3

# Summarize session-log.jsonl deny rate plus semantic uncached / INFERRED counts
session-report:
    @python scripts/report_session_log.py
    @uv tool run --from graphifyy python ./scripts/graphify_semantic.py status

# Show RTK LLM token reduction analytics dashboard
rtk-gain:
    @rtk gain

# Show RTK recent command execution history with savings breakdown
rtk-history:
    @rtk gain --history

# Discover missed token-saving opportunities from agent history
rtk-discover:
    @rtk discover

# Update RTK to the latest release, re-sync agent rules, and run verification
update-rtk:
    @pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/03_setup_runtimes.ps1 -OnlyRtk -Force
    @just sync-rules
    @just test

# Update graphify engine, refresh git hooks, re-sync agent rules, and verify
update-graphify:
    @uv tool install --upgrade --with watchdog "graphifyy[mcp]"
    @graphify hook install
    @just sync-rules
    @just test
