#Requires -Version 5.1
<#
.SYNOPSIS
    configs/agents/ 内の SSOT ルール＆スキルをグローバルエージェント環境へ一括同期します。
.DESCRIPTION
    正本 (configs/agents/) から以下へ同期します:
    - Antigravity: ~/.gemini/config/*, ~/.agents/rules|workflows|skills, MCP merge
    - Claude Code: ~/.claude/CLAUDE.md, ~/.claude/skills/...
    - Cursor:      %APPDATA%/Cursor/User/AGENTS.md, ~/.cursor/rules/graphify.mdc
    - Workspace:   CLAUDE.md, .cursorrules, .agents/mcp_config.json (gitignored)
    vendor の広義 graphify スキルは除去し、graphify-navigator を SSOT とします。
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

$masterRules = Join-Path $configsDir "agents\AGENTS.md"
$masterBrowserAgentDir = Join-Path $configsDir "agents\skills\browser-agent"
$masterModernCliDir = Join-Path $configsDir "agents\skills\modern-cli-expert"
$masterGraphifyNavDir = Join-Path $configsDir "agents\skills\graphify-navigator"
$masterAntigravityDir = Join-Path $configsDir "agents\antigravity"
$masterCursorRulesDir = Join-Path $configsDir "agents\cursor\rules"
$masterAgentsDir = Join-Path $configsDir "agents"
$mcpTemplate = Join-Path $masterAntigravityDir "mcp_config.json"

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

function Resolve-GraphifyMcpExe {
    $cmd = Get-Command graphify-mcp -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) { return $cmd.Source }
    $fallback = Join-Path $env:USERPROFILE ".local\bin\graphify-mcp.exe"
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Test-GraphifyMcpCommandValid {
    param([string]$Command)
    if (-not $Command) { return $false }
    if ($Command -match '(?i)(^|[\\/])uv(\.exe)?$') { return $false }
    if ($Command -eq "graphify-mcp" -or $Command -eq "graphify-mcp.exe") { return $false }
    if ($Command -match '(?i)\.exe$' -or $Command -match '^[A-Za-z]:\\' -or $Command -match '^/') {
        return (Test-Path $Command)
    }
    return $false
}

function New-MaterializedGraphifyServer {
    param([object]$TemplateServer)
    if (-not $TemplateServer) { return $null }

    $exe = Resolve-GraphifyMcpExe
    if (-not $exe) {
        # Never materialize bare "graphify-mcp" — PATH-dependent and fails verify_tools.
        return $null
    }

    $argsList = @()
    if ($TemplateServer.args) {
        foreach ($a in @($TemplateServer.args)) { $argsList += [string]$a }
    }
    # Strip uv-tool-run arg prefixes if a stale template somehow still has them
    if ($argsList -contains "tool" -and $argsList -contains "run") {
        $argsList = @('${workspace.path}/graphify-out/graph.json')
    }
    if ($argsList.Count -eq 0) {
        $argsList = @('${workspace.path}/graphify-out/graph.json')
    }

    $envObj = [PSCustomObject]@{
        PYTHONUTF8       = "1"
        PYTHONIOENCODING = "utf-8"
    }
    if ($TemplateServer.env) {
        foreach ($p in $TemplateServer.env.PSObject.Properties) {
            $envObj | Add-Member -NotePropertyName $p.Name -NotePropertyValue ([string]$p.Value) -Force
        }
    }

    return [PSCustomObject]@{
        command = $exe
        args    = $argsList
        env     = $envObj
    }
}

function Test-GraphifyMcpInSync {
    param([string]$TemplatePath, [string]$DestPath)
    if (-not (Test-Path $TemplatePath)) { return $false }

    $template = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $want = New-MaterializedGraphifyServer -TemplateServer $template.mcpServers.graphify

    if (-not $want) {
        # graphify-mcp not installed: OK if dest missing or has no graphify entry;
        # OK if dest already has a valid absolute path; DIFF if stale bare/uv config.
        if (-not (Test-Path $DestPath)) { return $true }
        try {
            $dest = [System.IO.File]::ReadAllText($DestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if (-not $dest.mcpServers -or -not $dest.mcpServers.graphify) { return $true }
            $cmd = [string]$dest.mcpServers.graphify.command
            return (Test-GraphifyMcpCommandValid -Command $cmd)
        } catch {
            return $false
        }
    }

    if (-not (Test-Path $DestPath)) { return $false }
    try {
        $dest = [System.IO.File]::ReadAllText($DestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $have = $dest.mcpServers.graphify
        if (-not $have) { return $false }
        $wantNorm = Get-NormalizedJsonText -JsonText ($want | ConvertTo-Json -Depth 20)
        $haveNorm = Get-NormalizedJsonText -JsonText ($have | ConvertTo-Json -Depth 20)
        return ($wantNorm -eq $haveNorm)
    } catch {
        return $false
    }
}

function Merge-GraphifyMcpConfig {
    param([string]$TemplatePath, [string]$DestPath)
    if (-not (Test-Path $TemplatePath)) {
        Write-Warning "[SKIP] MCP template missing: $TemplatePath"
        return
    }
    if (Test-GraphifyMcpInSync -TemplatePath $TemplatePath -DestPath $DestPath) {
        Write-Host "  [OK] MCP graphify already in sync -> $DestPath" -ForegroundColor DarkGray
        $script:skippedCount++
        return
    }

    $template = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8).Trim() | ConvertFrom-Json
    $graphifyServer = New-MaterializedGraphifyServer -TemplateServer $template.mcpServers.graphify
    if (-not $graphifyServer) {
        if (-not $template.mcpServers.graphify) {
            Write-Warning "[SKIP] Template has no mcpServers.graphify"
        } else {
            Write-Warning "[SKIP] graphify-mcp not found; MCP merge skipped. Run scripts/03_setup_runtimes.ps1 (or: uv tool install graphifyy[mcp]) then re-run sync-rules."
        }
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
    Write-Host "  [SYNCED] MCP graphify -> $DestPath" -ForegroundColor Green
    $script:syncedCount++
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
    @{ Name = "Antigravity Global Rules";            Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config") "AGENTS.md"; IsDir = $false },
    @{ Name = "Claude Code Global Rules";            Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude") "CLAUDE.md";        IsDir = $false },
    @{ Name = "Cursor Global Rules";                 Src = $masterRules; Dest = Join-Path (Join-Path $env:APPDATA "Cursor\User") "AGENTS.md";       IsDir = $false },
    @{ Name = "Antigravity Global Modern-CLI";       Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "modern-cli-expert"; IsDir = $true },
    @{ Name = "Claude Code Global Modern-CLI";       Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Agents Skills Modern-CLI";            Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Antigravity Global Browser-Agent";    Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "browser-agent"; IsDir = $true },
    @{ Name = "Claude Code Global Browser-Agent";    Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "browser-agent";        IsDir = $true },
    @{ Name = "Agents Skills Browser-Agent";         Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "browser-agent";        IsDir = $true },
    @{ Name = "Antigravity Global Graphify-Nav";     Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "graphify-navigator"; IsDir = $true },
    @{ Name = "Claude Code Global Graphify-Nav";     Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "graphify-navigator";        IsDir = $true },
    @{ Name = "Agents Skills Graphify-Nav";          Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "graphify-navigator";        IsDir = $true },
    @{ Name = "Antigravity Global Graphify Rule";    Src = (Join-Path $masterAntigravityDir "rules\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\rules") "graphify.md"; IsDir = $false },
    @{ Name = "Antigravity Global Graphify Workflow";Src = (Join-Path $masterAntigravityDir "workflows\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\workflows") "graphify.md"; IsDir = $false },
    @{ Name = "Agents Always-on Graphify Rule";      Src = (Join-Path $masterAntigravityDir "rules\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\rules") "graphify.md"; IsDir = $false },
    @{ Name = "Agents Graphify Workflow";            Src = (Join-Path $masterAntigravityDir "workflows\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\workflows") "graphify.md"; IsDir = $false },
    @{ Name = "Cursor Always-on Graphify Rule";      Src = (Join-Path $masterCursorRulesDir "graphify.mdc"); Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\rules") "graphify.mdc"; IsDir = $false },
    @{ Name = "Workspace Claude Code Guide";         Src = $projectAgentsMd; Dest = $projectClaudeMd;    IsDir = $false },
    @{ Name = "Workspace Cursor Rules";              Src = $projectAgentsMd; Dest = $projectCursorRules; IsDir = $false }
)

# Broad vendor "graphify" skills conflict with SSOT graphify-navigator.
$vendorGraphifySkillDirs = @(
    (Join-Path $env:USERPROFILE ".agents\skills\graphify")
    (Join-Path $env:USERPROFILE ".claude\skills\graphify")
    (Join-Path $env:USERPROFILE ".gemini\config\skills\graphify")
    (Join-Path $env:USERPROFILE ".codex\skills\graphify")
    (Join-Path $env:USERPROFILE ".config\opencode\skills\graphify")
    (Join-Path $env:USERPROFILE ".copilot\skills\graphify")
    (Join-Path $env:USERPROFILE ".codebuddy\skills\graphify")
    (Join-Path $env:USERPROFILE ".kimi\skills\graphify")
    (Join-Path $rootDir ".agents\skills\graphify")
    (Join-Path $rootDir ".claude\skills\graphify")
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

$mcpTargets = @(
    (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json")
    (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
    (Join-Path $rootDir ".agents\mcp_config.json")
)

Write-Host "`n>> Graphify MCP (merge; absolute graphify-mcp path)..." -ForegroundColor Cyan
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
