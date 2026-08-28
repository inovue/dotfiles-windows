#Requires -Version 5.1
<#
.SYNOPSIS
    Cursor-only: configs/agents/ 内の SSOT ルール＆スキルを Cursor 環境へ同期します。
.DESCRIPTION
    正本 (configs/agents/GLOBAL_RULES.md ほか) から Cursor ターゲットのみへ同期します:
    - Cursor User: %APPDATA%/Cursor/User/AGENTS.md
    - Cursor global: ~/.cursor/skills/*, ~/.cursor/mcp.json (graph unpinned)
    - Workspace:   .cursor/mcp.json
    - RTK config:  %APPDATA%/rtk/config.toml, ~/.config/rtk/config.toml
    ~/.cursor/hooks.json は公式 `rtk init -g --agent cursor` の所有。このスクリプトは上書きしない。
    他プロダクトへは書きません。リポジトリ直下の余分な always-on markdown は
    stale mirror として除去します。
    leftover graphify / rtk-expert / impeccable-agile / agent_guard は除去します。
.PARAMETER Check
    同期せず差分のみ検査（終了コード 0: 一致, 1: 差分あり）。
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$configsDir = Join-Path $rootDir "configs"

$masterRules = Join-Path $configsDir "agents\GLOBAL_RULES.md"
$masterBrowserAgentDir = Join-Path $configsDir "agents\skills\browser-agent"
$masterModernCliDir = Join-Path $configsDir "agents\skills\modern-cli-expert"
$masterTuiWireframeDir = Join-Path $configsDir "agents\skills\tui-wireframe-designer"
$masterRtkConfig = Join-Path $configsDir "rtk\config.toml"
$mcpTemplate = Join-Path $configsDir "agents\cursor\mcp_config.json"

if (-not (Test-Path $masterRules)) {
    Write-Error "正本ルールファイルが見つかりません: $masterRules"
    exit 1
}

function Test-TextFilesIdentical {
    param ([string]$File1, [string]$File2)
    if (-not (Test-Path $File1) -or -not (Test-Path $File2)) { return $false }
    try {
        $text1 = [System.IO.File]::ReadAllText($File1, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimEnd()
        $text2 = [System.IO.File]::ReadAllText($File2, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimEnd()
        return ($text1 -eq $text2)
    } catch {
        return $false
    }
}

function Test-DirectoriesIdentical {
    param ([string]$SrcDir, [string]$DestDir)
    if (-not (Test-Path $SrcDir) -or -not (Test-Path $DestDir)) { return $false }
    try {
        $srcFiles = @(Get-ChildItem -Path $SrcDir -Recurse -File | ForEach-Object {
            $_.FullName.Substring($SrcDir.Length).TrimStart('\', '/').Replace('\', '/')
        } | Sort-Object)
        $destFiles = @(Get-ChildItem -Path $DestDir -Recurse -File | ForEach-Object {
            $_.FullName.Substring($DestDir.Length).TrimStart('\', '/').Replace('\', '/')
        } | Sort-Object)
        if ($srcFiles.Count -ne $destFiles.Count) { return $false }
        for ($i = 0; $i -lt $srcFiles.Count; $i++) {
            if ($srcFiles[$i] -ne $destFiles[$i]) { return $false }
            $sPath = Join-Path $SrcDir ($srcFiles[$i] -replace '/', '\')
            $dPath = Join-Path $DestDir ($destFiles[$i] -replace '/', '\')
            if (-not (Test-TextFilesIdentical -File1 $sPath -File2 $dPath)) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

function Sync-DirectoryMirror {
    param ([string]$SrcDir, [string]$DestDir)
    if (Test-Path $DestDir) {
        Remove-Item -Path $DestDir -Recurse -Force
    }
    New-Item -Path $DestDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $SrcDir '*') -Destination $DestDir -Recurse -Force
}

function Test-OfficialCursorRtkHook {
    $hooksPath = Join-Path (Join-Path $env:USERPROFILE ".cursor") "hooks.json"
    if (-not (Test-Path $hooksPath)) { return $false }
    try {
        $raw = [System.IO.File]::ReadAllText($hooksPath)
        return ($raw -match 'rtk hook cursor') -and ($raw -notmatch 'agent_guard')
    } catch {
        return $false
    }
}

function Get-NormalizedJsonText {
    param([string]$JsonText)
    if (-not $JsonText) { return "" }
    try {
        $obj = $JsonText | ConvertFrom-Json
        return (($obj | ConvertTo-Json -Depth 20 -Compress) -replace '\s+', ' ').Trim()
    } catch {
        return $JsonText.Replace("`r`n", "`n").Trim()
    }
}

function Test-GraphifyMcpRemoved {
    param([string]$DestPath)
    if (-not (Test-Path $DestPath)) { return $true }
    try {
        $dest = [System.IO.File]::ReadAllText($DestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not $dest.mcpServers) { return $true }
        return -not ($dest.mcpServers.PSObject.Properties.Name -contains "graphify")
    } catch {
        return $false
    }
}

function Remove-GraphifyMcpConfig {
    param([string]$DestPath)
    if (-not (Test-Path $DestPath)) { return }
    try {
        $dest = [System.IO.File]::ReadAllText($DestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        Write-Warning "[SKIP] MCP parse failed: $DestPath"
        return
    }
    if (-not $dest.mcpServers) { return }
    if (-not ($dest.mcpServers.PSObject.Properties.Name -contains "graphify")) {
        Write-Host "  [OK] MCP has no graphify entry -> $DestPath" -ForegroundColor DarkGray
        $script:skippedCount++
        return
    }
    $dest.mcpServers.PSObject.Properties.Remove("graphify")
    $json = $dest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($DestPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [REMOVED] MCP graphify -> $DestPath" -ForegroundColor Green
    $script:syncedCount++
}

Write-Host "   Cursor-only SSOT Rule & Skill Synchronizer         " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Master Rules: $masterRules" -ForegroundColor Gray
Write-Host "MCP template: $mcpTemplate`n" -ForegroundColor Gray

$hasDiff = $false
$fatalError = $false
$syncedCount = 0
$skippedCount = 0

Write-Host ">> Synchronizing Global AI Agent Configurations..." -ForegroundColor Cyan

$allTargets = @(
    @{ Name = "Cursor Global Rules";                 Src = $masterRules; Dest = Join-Path (Join-Path $env:APPDATA "Cursor\User") "AGENTS.md";       IsDir = $false },
    @{ Name = "Cursor Global Modern-CLI";            Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Cursor Global Browser-Agent";         Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "browser-agent";        IsDir = $true },
    @{ Name = "Cursor Global Tui-Wireframe";         Src = $masterTuiWireframeDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "tui-wireframe-designer";        IsDir = $true },
    @{ Name = "RTK Global Config (AppData)";         Src = $masterRtkConfig; Dest = Join-Path (Join-Path $env:APPDATA "rtk") "config.toml";                                     IsDir = $false },
    @{ Name = "RTK User Config (.config)";           Src = $masterRtkConfig; Dest = Join-Path (Join-Path (Join-Path $env:USERPROFILE ".config") "rtk") "config.toml";            IsDir = $false }
)

# leftover graphify skills (vendor + previously deployed SSOT copies)
$vendorGraphifySkillDirs = @(
    (Join-Path $env:USERPROFILE ".cursor\skills\graphify-navigator")
    (Join-Path $env:USERPROFILE ".cursor\skills\graphify-builder")
    (Join-Path $env:USERPROFILE ".agents\skills\graphify")
    (Join-Path $env:USERPROFILE ".claude\skills\graphify")
    (Join-Path $env:USERPROFILE ".cursor\skills\graphify")
    (Join-Path $env:USERPROFILE ".gemini\config\skills\graphify")
    (Join-Path $env:USERPROFILE ".codex\skills\graphify")
    (Join-Path $env:USERPROFILE ".config\opencode\skills\graphify")
    (Join-Path $env:USERPROFILE ".copilot\skills\graphify")
    (Join-Path $env:USERPROFILE ".codebuddy\skills\graphify")
    (Join-Path $env:USERPROFILE ".kimi\skills\graphify")
    (Join-Path $rootDir ".agents\skills\graphify")
    (Join-Path $rootDir ".claude\skills\graphify")
    (Join-Path $rootDir ".cursor\skills\graphify")
    (Join-Path $env:USERPROFILE ".cursor\skills\rtk-expert")
    (Join-Path $env:USERPROFILE ".cursor\skills\impeccable-agile")
)

foreach ($target in $allTargets) {
    if (-not (Test-Path $target.Src)) {
        Write-Warning "[MISSING] Source missing: $($target.Src)"
        $hasDiff = $true
        continue
    }

    $isIdentical = $false
    if ($target.IsDir) {
        $isIdentical = Test-DirectoriesIdentical -SrcDir $target.Src -DestDir $target.Dest
    } else {
        $isIdentical = Test-TextFilesIdentical -File1 $target.Src -File2 $target.Dest
    }

    if ($isIdentical) {
        Write-Host "  [OK] $($target.Name) is already in sync." -ForegroundColor DarkGray
        $skippedCount++
    } else {
        $hasDiff = $true
        if ($Check) {
            Write-Host "  [DIFF] $($target.Name) differs from master!" -ForegroundColor Yellow
        } else {
            if ($target.IsDir) {
                Sync-DirectoryMirror -SrcDir $target.Src -DestDir $target.Dest
            } else {
                $destDir = Split-Path -Parent $target.Dest
                if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
                Copy-Item -Path $target.Src -Destination $target.Dest -Force
            }
            Write-Host "  [SYNCED] $($target.Name) -> $($target.Dest)" -ForegroundColor Green
            $syncedCount++
        }
    }
}

Write-Host "`n>> Official Cursor rtk hook (~/.cursor/hooks.json, not SSOT)..." -ForegroundColor Cyan
$rtkHookHint = "rtk init -g --agent cursor --hook-only --auto-patch"
if (Test-OfficialCursorRtkHook) {
    Write-Host "  [OK] ~/.cursor/hooks.json has rtk hook cursor (no agent_guard)." -ForegroundColor DarkGray
    $skippedCount++
} else {
    $hasDiff = $true
    if ($Check) {
        Write-Host "  [DIFF] Official Cursor rtk hook missing. Run: $rtkHookHint" -ForegroundColor Yellow
    } else {
        $rtkCmd = Get-Command rtk -ErrorAction SilentlyContinue
        if ($rtkCmd) {
            $hooksPath = Join-Path (Join-Path $env:USERPROFILE ".cursor") "hooks.json"
            if ((Test-Path $hooksPath) -and ((Get-Content -Raw -Path $hooksPath) -match 'agent_guard')) {
                Remove-Item -Path $hooksPath -Force
                Write-Host "  [REMOVED] leftover agent_guard from ~/.cursor/hooks.json" -ForegroundColor Green
            }
            & rtk init -g --agent cursor --hook-only --auto-patch
            if ($LASTEXITCODE -eq 0 -and (Test-OfficialCursorRtkHook)) {
                Write-Host "  [SYNCED] Official Cursor rtk hook via rtk init." -ForegroundColor Green
                $syncedCount++
            } else {
                Write-Warning "rtk init did not install rtk hook cursor. Run: $rtkHookHint"
                $fatalError = $true
            }
        } else {
            Write-Warning "rtk not in PATH. Install via 03_setup_runtimes.ps1 then: $rtkHookHint"
            $fatalError = $true
        }
    }
}

$mcpTargets = @(
    (Join-Path $env:USERPROFILE ".cursor\mcp.json")
    (Join-Path $rootDir ".cursor\mcp.json")
)

Write-Host "`n>> MCP: ensure graphify server is absent..." -ForegroundColor Cyan
foreach ($mcpDest in $mcpTargets) {
    if ($Check) {
        if (Test-GraphifyMcpRemoved -DestPath $mcpDest) {
            Write-Host "  [OK] MCP has no graphify -> $mcpDest" -ForegroundColor DarkGray
            $skippedCount++
        } else {
            Write-Host "  [DIFF] MCP still has graphify -> $mcpDest" -ForegroundColor Yellow
            $hasDiff = $true
        }
    } else {
        Remove-GraphifyMcpConfig -DestPath $mcpDest
    }
}

# Duplicated always-on mirrors bloat every agent turn and dilute instruction priority.
# leftover always-on graphify.mdc would tax every workspace.
$staleWorkspaceMirrors = @(
    (Join-Path $rootDir ".cursorrules")
    (Join-Path $rootDir ".cursor\rules\graphify.mdc")
    (Join-Path (Join-Path $env:USERPROFILE ".cursor\rules") "graphify.mdc")
    (Join-Path $rootDir ".cursor\hooks.json")
    (Join-Path (Join-Path $env:USERPROFILE ".cursor\scripts") "agent_guard.py")
)
$allowedRootMd = @("AGENTS.md", "README.md")
Get-ChildItem -Path $rootDir -File -Filter "*.md" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($allowedRootMd -notcontains $_.Name) {
        $staleWorkspaceMirrors += $_.FullName
    }
}
Write-Host "`n>> Checking for stale duplicated workspace rule mirrors..." -ForegroundColor Cyan
foreach ($stale in $staleWorkspaceMirrors) {
    if (Test-Path $stale) {
        $hasDiff = $true
        if ($Check) {
            Write-Host "  [DIFF] Stale duplicated mirror present: $stale" -ForegroundColor Yellow
        } else {
            Remove-Item -Path $stale -Force
            Write-Host "  [REMOVED] Stale duplicated mirror: $stale" -ForegroundColor Green
            $syncedCount++
        }
    } else {
        Write-Host "  [OK] No stale mirror at $stale" -ForegroundColor DarkGray
        $skippedCount++
    }
}

Write-Host "`n>> Checking for conflicting vendor graphify skills..." -ForegroundColor Cyan
foreach ($vendorDir in $vendorGraphifySkillDirs) {
    if (Test-Path $vendorDir) {
        $hasDiff = $true
        if ($Check) {
            Write-Host "  [DIFF] Conflicting vendor skill present: $vendorDir" -ForegroundColor Yellow
        } else {
            Remove-Item -Path $vendorDir -Recurse -Force
            Write-Host "  [REMOVED] Conflicting vendor skill: $vendorDir" -ForegroundColor Green
            $syncedCount++
        }
    } else {
        Write-Host "  [OK] No vendor conflict at $vendorDir" -ForegroundColor DarkGray
        $skippedCount++
    }
}

if ($Check) {
    Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
    if ($hasDiff) {
        Write-Host "Result: Differences detected between master and global targets." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "Result: All global targets are perfectly in sync with master SSOT." -ForegroundColor Green
        exit 0
    }
} else {
    Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Sync Completed: $syncedCount synced, $skippedCount already up to date." -ForegroundColor Green
    if ($fatalError) {
        Write-Warning "Result: fatal sync error (official Cursor rtk hook)."
        exit 1
    }
}
