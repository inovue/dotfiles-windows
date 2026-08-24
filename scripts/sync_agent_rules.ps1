#Requires -Version 5.1
<#
.SYNOPSIS
    configs/agents/ 内の SSOT (Single Source of Truth) ルール＆スキルを各エージェントおよびワークスペースに一括同期します。
.DESCRIPTION
    正本 (configs/agents/AGENTS.md, configs/agents/skills/...) から以下の配置先へ同期します:
    - ワークスペース: AGENTS.md, CLAUDE.md, .cursorrules, .agents/skills/..., .cursor/rules/...
    - グローバル: ~/.gemini/config/, ~/.claude/, %APPDATA%/Cursor/User/
.PARAMETER WorkspaceOnly
    ワークスペース内のファイルのみ同期します。
.PARAMETER GlobalOnly
    ユーザーのグローバル設定ディレクトリのみ同期します。
.PARAMETER Check
    同期は行わず、正本との間に差分があるかどうかのみをチェックします（終了コード 0: 差分なし, 1: 差分あり）。
#>
[CmdletBinding()]
param(
    [switch]$WorkspaceOnly,
    [switch]$GlobalOnly,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$configsDir = Join-Path $rootDir "configs"

$masterRules = Join-Path $configsDir "agents\AGENTS.md"
$masterSkill = Join-Path $configsDir "agents\skills\modern-cli-expert\SKILL.md"
$masterBrowserAgentDir = Join-Path $configsDir "agents\skills\browser-agent"

if (-not (Test-Path $masterRules)) {
    Write-Error "正本ルールファイルが見つかりません: $masterRules"
    exit 1
}

$syncTargets = @()

# 1. ワークスペース内ターゲット
if (-not $GlobalOnly) {
    $syncTargets += @(
        @{ Name = "Workspace AGENTS.md";        Src = $masterRules; Dest = Join-Path $rootDir "AGENTS.md" },
        @{ Name = "Workspace CLAUDE.md";        Src = $masterRules; Dest = Join-Path $rootDir "CLAUDE.md" },
        @{ Name = "Workspace .cursorrules";     Src = $masterRules; Dest = Join-Path $rootDir ".cursorrules" },
        @{ Name = "Workspace Modern-CLI Skill"; Src = $masterSkill; Dest = Join-Path $rootDir ".agents\skills\modern-cli-expert\SKILL.md" },
        @{ Name = "Cursor MDC Rules";           Src = $masterSkill; Dest = Join-Path $rootDir ".cursor\rules\modern-cli.mdc" },
        @{ Name = "Workspace Browser-Agent";    Src = $masterBrowserAgentDir; Dest = Join-Path $rootDir ".agents\skills\browser-agent" }
    )
}

# 2. ユーザーグローバル設定ターゲット
if (-not $WorkspaceOnly) {
    $syncTargets += @(
        @{ Name = "Antigravity Global Rules";       Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config") "AGENTS.md" },
        @{ Name = "Claude Code Global Rules";       Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude") "CLAUDE.md" },
        @{ Name = "Cursor Global Rules";            Src = $masterRules; Dest = Join-Path (Join-Path $env:APPDATA "Cursor\User") "AGENTS.md" },
        @{ Name = "Antigravity Global Modern-CLI";  Src = $masterSkill; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills\modern-cli-expert") "SKILL.md" },
        @{ Name = "Claude Code Global Modern-CLI";  Src = $masterSkill; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills\modern-cli-expert") "SKILL.md" },
        @{ Name = "Antigravity Global Browser-Agent"; Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "browser-agent" },
        @{ Name = "Claude Code Global Browser-Agent"; Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "browser-agent" }
    )
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "   AI Agent SSOT Rule & Skill Synchronizer            " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Master Rules: $masterRules" -ForegroundColor Gray
Write-Host "Master Skill: $masterSkill`n" -ForegroundColor Gray

$hasDiff = $false
$syncedCount = 0
$skippedCount = 0

foreach ($target in $syncTargets) {
    if (-not (Test-Path $target.Src)) {
        Write-Warning "[SKIP] Source missing: $($target.Src)"
        continue
    }

    $isDir = Test-Path -PathType Container $target.Src
    $isIdentical = $true

    if ($isDir) {
        if (-not (Test-Path $target.Dest)) {
            $isIdentical = $false
        } else {
            $srcFiles = Get-ChildItem -Path $target.Src -Recurse -File
            foreach ($sFile in $srcFiles) {
                $rel = $sFile.FullName.Substring($target.Src.Length).TrimStart('\', '/')
                $dFilePath = Join-Path $target.Dest $rel
                if (-not (Test-Path $dFilePath)) {
                    $isIdentical = $false
                    break
                }
                $sBytes = [System.IO.File]::ReadAllBytes($sFile.FullName)
                $dBytes = [System.IO.File]::ReadAllBytes($dFilePath)
                if ($sBytes.Length -ne $dBytes.Length) {
                    $isIdentical = $false
                    break
                }
                for ($i = 0; $i -lt $sBytes.Length; $i++) {
                    if ($sBytes[$i] -ne $dBytes[$i]) {
                        $isIdentical = $false
                        break
                    }
                }
                if (-not $isIdentical) { break }
            }
        }
    } else {
        $destDir = Split-Path -Parent $target.Dest
        if (-not (Test-Path $destDir) -and -not $Check) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $target.Dest)) {
            $isIdentical = $false
        } else {
            $srcBytes = [System.IO.File]::ReadAllBytes($target.Src)
            $destBytes = [System.IO.File]::ReadAllBytes($target.Dest)
            if ($srcBytes.Length -eq $destBytes.Length) {
                for ($i = 0; $i -lt $srcBytes.Length; $i++) {
                    if ($srcBytes[$i] -ne $destBytes[$i]) {
                        $isIdentical = $false
                        break
                    }
                }
            } else {
                $isIdentical = $false
            }
        }
    }

    if ($isIdentical) {
        Write-Host "  [OK] $($target.Name) is already in sync." -ForegroundColor DarkGray
        $skippedCount++
    } else {
        $hasDiff = $true
        if ($Check) {
            Write-Host "  [DIFF] $($target.Name) differs from master!" -ForegroundColor Yellow
        } else {
            if ($isDir) {
                if (-not (Test-Path $target.Dest)) { New-Item -Path $target.Dest -ItemType Directory -Force | Out-Null }
                Copy-Item -Path "$($target.Src)\*" -Destination $target.Dest -Recurse -Force
            } else {
                Copy-Item -Path $target.Src -Destination $target.Dest -Force
            }
            Write-Host "  [SYNCED] $($target.Name) -> $($target.Dest)" -ForegroundColor Green
            $syncedCount++
        }
    }
}

Write-Host "-------------------------------------------------------" -ForegroundColor Cyan
if ($Check) {
    if ($hasDiff) {
        Write-Host "Result: Differences detected between master and targets." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "Result: All targets are perfectly in sync with master." -ForegroundColor Green
        exit 0
    }
} else {
    Write-Host "Sync Completed: $syncedCount synced, $skippedCount up to date." -ForegroundColor Green
}
