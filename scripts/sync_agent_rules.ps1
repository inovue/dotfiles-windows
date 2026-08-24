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
$masterGraphifyNavDir = Join-Path $configsDir "agents\skills\graphify-navigator"
$masterAntigravityDir = Join-Path $configsDir "agents\antigravity"
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
    @{ Name = "Antigravity Global Graphify-Nav"; Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "graphify-navigator"; IsDir = $true },
    @{ Name = "Claude Code Global Graphify-Nav"; Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "graphify-navigator";        IsDir = $true },
    @{ Name = "Agents Skills Graphify-Nav";     Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "graphify-navigator"; IsDir = $true },
    @{ Name = "Antigravity Always-on Graphify Rule"; Src = (Join-Path $masterAntigravityDir "rules\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\rules") "graphify.md"; IsDir = $false },
    @{ Name = "Antigravity Graphify Workflow"; Src = (Join-Path $masterAntigravityDir "workflows\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\workflows") "graphify.md"; IsDir = $false },
    @{ Name = "Cursor Always-on Graphify Rule"; Src = (Join-Path $configsDir "agents\cursor\rules\graphify.mdc"); Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\rules") "graphify.mdc"; IsDir = $false },

    # --- 2. Workspace Navigation & Rule Mirrors (from root AGENTS.md) ---
    @{ Name = "Workspace Claude Code Guide";    Src = $projectAgentsMd; Dest = $projectClaudeMd;    IsDir = $false },
    @{ Name = "Workspace Cursor Rules";         Src = $projectAgentsMd; Dest = $projectCursorRules; IsDir = $false }
)

# Vendor `graphify install` drops a broad "any codebase question" skill named `graphify`
# alongside our SSOT `graphify-navigator`. That dual routing destabilizes agents.
$vendorGraphifySkillDirs = @(
    Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "graphify"
    Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "graphify"
    Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "graphify"
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

# --- 3. Antigravity MCP: upsert graphify server (merge, never wipe other servers) ---
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

function Test-GraphifyMcpInSync {
    param(
        [string]$TemplatePath,
        [string]$DestPath
    )
    if (-not (Test-Path $TemplatePath)) { return $false }
    if (-not (Test-Path $DestPath)) { return $false }
    try {
        $template = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $dest = [System.IO.File]::ReadAllText($DestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $want = Get-NormalizedJsonText -JsonText (($template.mcpServers.graphify | ConvertTo-Json -Depth 20))
        $have = Get-NormalizedJsonText -JsonText (($dest.mcpServers.graphify | ConvertTo-Json -Depth 20))
        return ($want -and $have -and ($want -eq $have))
    } catch {
        return $false
    }
}

function Merge-GraphifyMcpConfig {
    param(
        [string]$TemplatePath,
        [string]$DestPath
    )
    if (-not (Test-Path $TemplatePath)) {
        Write-Warning "[SKIP] MCP template missing: $TemplatePath"
        return
    }

    if (Test-GraphifyMcpInSync -TemplatePath $TemplatePath -DestPath $DestPath) {
        Write-Host "  [OK] Antigravity MCP graphify already in sync -> $DestPath" -ForegroundColor DarkGray
        $script:skippedCount++
        return
    }

    $templateRaw = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8).Trim()
    if (-not $templateRaw) {
        Write-Warning "[SKIP] MCP template empty: $TemplatePath"
        return
    }
    $template = $templateRaw | ConvertFrom-Json
    $graphifyServer = $template.mcpServers.graphify
    if (-not $graphifyServer) {
        Write-Warning "[SKIP] Template has no mcpServers.graphify"
        return
    }

    $destDir = Split-Path -Parent $DestPath
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    $destObj = $null
    if (Test-Path $DestPath) {
        $destRaw = [System.IO.File]::ReadAllText($DestPath, [System.Text.Encoding]::UTF8).Trim()
        if ($destRaw) {
            try { $destObj = $destRaw | ConvertFrom-Json } catch { $destObj = $null }
        }
    }
    if (-not $destObj) {
        $destObj = [PSCustomObject]@{ mcpServers = [PSCustomObject]@{} }
    }
    if (-not $destObj.mcpServers) {
        $destObj | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $destObj.mcpServers | Add-Member -NotePropertyName graphify -NotePropertyValue $graphifyServer -Force

    $json = $destObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($DestPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [SYNCED] Antigravity MCP graphify -> $DestPath" -ForegroundColor Green
    $script:syncedCount++
}

$mcpTemplate = Join-Path $masterAntigravityDir "mcp_config.json"
$mcpTargets = @(
    (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
    (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
)

Write-Host "`n>> Graphify MCP (Antigravity merge)..." -ForegroundColor Cyan
foreach ($mcpDest in $mcpTargets) {
    if ($Check) {
        if (Test-GraphifyMcpInSync -TemplatePath $mcpTemplate -DestPath $mcpDest) {
            Write-Host "  [OK] MCP graphify in sync -> $mcpDest" -ForegroundColor DarkGray
            $skippedCount++
        } else {
            Write-Host "  [DIFF] MCP graphify differs or missing -> $mcpDest" -ForegroundColor Yellow
            $hasDiff = $true
        }
    } else {
        Merge-GraphifyMcpConfig -TemplatePath $mcpTemplate -DestPath $mcpDest
    }
}

# --- 4. Remove conflicting vendor graphify skills (SSOT uses graphify-navigator) ---
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
}
