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
        @{ Name = "Cursor MDC Rules";           Src = $masterSkill; Dest = Join-Path $rootDir ".cursor\rules\modern-cli.mdc" }
    )
}

# 2. ユーザーグローバル設定ターゲット
if (-not $WorkspaceOnly) {
    $syncTargets += @(
        @{ Name = "Antigravity Global Rules";  Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config") "AGENTS.md" },
        @{ Name = "Claude Code Global Rules";  Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude") "CLAUDE.md" },
        @{ Name = "Cursor Global Rules";       Src = $masterRules; Dest = Join-Path (Join-Path $env:APPDATA "Cursor\User") "AGENTS.md" },
        @{ Name = "Antigravity Global Skill";  Src = $masterSkill; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills\modern-cli-expert") "SKILL.md" },
        @{ Name = "Claude Code Global Skill";  Src = $masterSkill; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills\modern-cli-expert") "SKILL.md" }
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

    $destDir = Split-Path -Parent $target.Dest
    if (-not (Test-Path $destDir)) {
        if (-not $Check) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }
    }

    $srcBytes = [System.IO.File]::ReadAllBytes($target.Src)
    $isIdentical = $false

    if (Test-Path $target.Dest) {
        $destBytes = [System.IO.File]::ReadAllBytes($target.Dest)
        if ($srcBytes.Length -eq $destBytes.Length) {
            $isIdentical = $true
            for ($i = 0; $i -lt $srcBytes.Length; $i++) {
                if ($srcBytes[$i] -ne $destBytes[$i]) {
                    $isIdentical = $false
                    break
                }
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
            [System.IO.File]::WriteAllBytes($target.Dest, $srcBytes)
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
