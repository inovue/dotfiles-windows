#Requires -Version 5.1
<#
.SYNOPSIS
    configs/agents/ 内の SSOT (Single Source of Truth) ルール＆スキルをユーザーのグローバルエージェント環境に一括同期します。
.DESCRIPTION
    正本 (configs/agents/AGENTS.md, configs/agents/skills/...) から以下のグローバル配置先へ同期します:
    - Antigravity: ~/.gemini/config/AGENTS.md, ~/.gemini/config/skills/...
    - Claude Code: ~/.claude/CLAUDE.md, ~/.claude/skills/...
    - Cursor:      %APPDATA%/Cursor/User/AGENTS.md
.PARAMETER Check
    同期は行わず、正本との間に差分があるかどうかのみをチェックします（終了コード 0: 正常, 1: 差分あり）。
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$configsDir = Join-Path $rootDir "configs"

$masterRules = Join-Path $configsDir "agents\AGENTS.md"
$masterBrowserAgentDir = Join-Path $configsDir "agents\skills\browser-agent"
$masterModernCliDir = Join-Path $configsDir "agents\skills\modern-cli-expert"
$masterAgentsDir = Join-Path $configsDir "agents"

if (-not (Test-Path $masterRules)) {
    Write-Error "正本ルールファイルが見つかりません: $masterRules"
    exit 1
}

# --- テキスト正規化比較関数 (LF/CRLF差分を無視) ---
function Test-TextFilesIdentical {
    param (
        [string]$File1,
        [string]$File2
    )
    if (-not (Test-Path $File1) -or -not (Test-Path $File2)) { return $false }
    try {
        $text1 = [System.IO.File]::ReadAllText($File1, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimEnd()
        $text2 = [System.IO.File]::ReadAllText($File2, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimEnd()
        return ($text1 -eq $text2)
    } catch {
        return $false
    }
}

# --- ディレクトリ再帰正規化比較関数 ---
function Test-DirectoriesIdentical {
    param (
        [string]$SrcDir,
        [string]$DestDir
    )
    if (-not (Test-Path $SrcDir) -or -not (Test-Path $DestDir)) { return $false }
    $srcFiles = Get-ChildItem -Path $SrcDir -Recurse -File
    foreach ($sFile in $srcFiles) {
        $rel = $sFile.FullName.Substring($SrcDir.Length).TrimStart('\', '/')
        $dFilePath = Join-Path $DestDir $rel
        if (-not (Test-Path $dFilePath)) { return $false }
        if (-not (Test-TextFilesIdentical -File1 $sFile.FullName -File2 $dFilePath)) {
            return $false
        }
    }
    return $true
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "   AI Agent SSOT Rule & Skill Synchronizer            " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Master Rules: $masterRules" -ForegroundColor Gray
Write-Host "Master Agents Dir: $masterAgentsDir`n" -ForegroundColor Gray

$hasDiff = $false
$syncedCount = 0
$skippedCount = 0

Write-Host ">> Synchronizing Global AI Agent Configurations..." -ForegroundColor Cyan

$projectAgentsMd = Join-Path $rootDir "AGENTS.md"
$projectClaudeMd = Join-Path $rootDir "CLAUDE.md"
$projectCursorRules = Join-Path $rootDir ".cursorrules"

$allTargets = @(
    # --- 1. Global AI Agent Rule & Skill Sync (from configs/agents/ SSOT) ---
    @{ Name = "Antigravity Global Rules";       Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config") "AGENTS.md"; IsDir = $false },
    @{ Name = "Claude Code Global Rules";       Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude") "CLAUDE.md";        IsDir = $false },
    @{ Name = "Cursor Global Rules";            Src = $masterRules; Dest = Join-Path (Join-Path $env:APPDATA "Cursor\User") "AGENTS.md";       IsDir = $false },
    @{ Name = "Antigravity Global Modern-CLI";  Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "modern-cli-expert"; IsDir = $true },
    @{ Name = "Claude Code Global Modern-CLI";  Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Antigravity Global Browser-Agent"; Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "browser-agent"; IsDir = $true },
    @{ Name = "Claude Code Global Browser-Agent"; Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "browser-agent";        IsDir = $true },

    # --- 2. Workspace Navigation & Rule Mirrors (from root AGENTS.md) ---
    @{ Name = "Workspace Claude Code Guide";    Src = $projectAgentsMd; Dest = $projectClaudeMd;    IsDir = $false },
    @{ Name = "Workspace Cursor Rules";         Src = $projectAgentsMd; Dest = $projectCursorRules; IsDir = $false }
)

foreach ($target in $allTargets) {
    if (-not (Test-Path $target.Src)) {
        Write-Warning "[SKIP] Source missing: $($target.Src)"
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
                if (-not (Test-Path $target.Dest)) { New-Item -Path $target.Dest -ItemType Directory -Force | Out-Null }
                Copy-Item -Path "$($target.Src)\*" -Destination $target.Dest -Recurse -Force
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

Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
if ($Check) {
    if ($hasDiff) {
        Write-Host "Result: Differences detected between master and global targets." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "Result: All global targets are perfectly in sync with master SSOT." -ForegroundColor Green
        exit 0
    }
} else {
    Write-Host "Sync Completed: $syncedCount synced, $skippedCount already up to date." -ForegroundColor Green
}
