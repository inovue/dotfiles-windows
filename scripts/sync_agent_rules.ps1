#Requires -Version 5.1
<#
.SYNOPSIS
    configs/agents/ 内の SSOT ルール＆スキルをグローバルエージェント環境へ一括同期します。
.DESCRIPTION
    正本 (configs/agents/GLOBAL_RULES.md ほか) から以下へ同期します:
    - Antigravity: ~/.gemini/config/*, ~/.agents/rules|workflows|skills, MCP merge
    - Claude Code: ~/.claude/CLAUDE.md, ~/.claude/skills/..., ~/.claude.json (MCP surgical merge)
    - Cursor:      %APPDATA%/Cursor/User/AGENTS.md, ~/.cursor/rules/graphify.mdc
    - Workspace:   CLAUDE.md (@AGENTS.md pointer), .agents/mcp_config.json (gitignored)
    アンチ重複: ワークスペースの .cursorrules / .cursor/rules/graphify.mdc は
    常時コンテキストの多重ロード源となるため存在すれば除去します。
    vendor の広義 graphify スキルは除去し、graphify-navigator / graphify-builder を SSOT とします。
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
$masterClaudeProjectPointer = Join-Path $configsDir "agents\claude\CLAUDE.project.md"
$masterBrowserAgentDir = Join-Path $configsDir "agents\skills\browser-agent"
$masterModernCliDir = Join-Path $configsDir "agents\skills\modern-cli-expert"
$masterGraphifyNavDir = Join-Path $configsDir "agents\skills\graphify-navigator"
$masterGraphifyBuilderDir = Join-Path $configsDir "agents\skills\graphify-builder"
$masterRtkExpertDir = Join-Path $configsDir "agents\skills\rtk-expert"
$masterRtkConfig = Join-Path $configsDir "rtk\config.toml"
$masterClaudeSettings = Join-Path $configsDir "agents\claude\settings.json"
$masterAntigravityDir = Join-Path $configsDir "agents\antigravity"
$masterCursorRulesDir = Join-Path $configsDir "agents\cursor\rules"
$masterCursorHooks = Join-Path $configsDir "agents\cursor\hooks.json"
$masterAgentsDir = Join-Path $configsDir "agents"
$masterHooks = Join-Path $masterAgentsDir "hooks.json"
$masterAgentGuard = Join-Path $rootDir "scripts\agent_guard.py"
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

function Get-HookContentWithGuardPath {
    # hooks.json master references the guard via workspace-relative path
    # ("python scripts/agent_guard.py"), which only resolves when CWD is this
    # repo root. Deployed copies must point to their co-deployed guard via an
    # absolute path, or every hook invocation fails in other workspaces.
    param([string]$SrcFile, [string]$GuardPath)
    $content = [System.IO.File]::ReadAllText($SrcFile, [System.Text.Encoding]::UTF8)
    $guardFwd = $GuardPath.Replace('\', '/')
    return $content.Replace('python scripts/agent_guard.py', "python $guardFwd")
}

function Test-TextContentIdentical {
    param([string]$Content, [string]$File)
    if (-not (Test-Path $File)) { return $false }
    try {
        $t1 = $Content.Replace("`r`n", "`n").TrimEnd()
        $t2 = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimEnd()
        return ($t1 -eq $t2)
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

function Test-McpDestIsWorkspaceLocal {
    # User-global MCP (cwd often $HOME) must not pin a graph path.
    # Workspace-local MCP can pin this repo's graph.json as an absolute path.
    param([string]$DestPath)
    if (-not $DestPath -or -not $rootDir) { return $false }
    try {
        $destFull = [System.IO.Path]::GetFullPath($DestPath)
        $rootFull = [System.IO.Path]::GetFullPath($rootDir)
    } catch {
        return $false
    }
    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    if ($destFull.Equals($rootFull, $cmp)) { return $true }
    $prefix = $rootFull.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $destFull.StartsWith($prefix, $cmp)
}

function New-MaterializedGraphifyServer {
    param(
        [object]$TemplateServer,
        [switch]$PinWorkspaceGraph
    )
    if (-not $TemplateServer) { return $null }

    $exe = Resolve-GraphifyMcpExe
    if (-not $exe) {
        # Never materialize bare "graphify-mcp" — PATH-dependent and fails verify_tools.
        return $null
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

    # Template args are ignored on purpose: a relative graphify-out/graph.json
    # copied into user-global MCP resolves against $HOME (Cursor field report
    # 2026-08-26). Never pin this repo into global configs either.
    $server = [PSCustomObject]@{
        command = $exe
        env     = $envObj
    }
    if ($PinWorkspaceGraph) {
        $graphJson = [System.IO.Path]::GetFullPath((Join-Path $rootDir "graphify-out\graph.json"))
        $server | Add-Member -NotePropertyName args -NotePropertyValue ([string[]]@($graphJson))
    }
    return $server
}

function Test-GraphifyMcpInSync {
    param([string]$TemplatePath, [string]$DestPath)
    if (-not (Test-Path $TemplatePath)) { return $false }

    $template = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $want = New-MaterializedGraphifyServer -TemplateServer $template.mcpServers.graphify -PinWorkspaceGraph:(Test-McpDestIsWorkspaceLocal -DestPath $DestPath)

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
    $graphifyServer = New-MaterializedGraphifyServer -TemplateServer $template.mcpServers.graphify -PinWorkspaceGraph:(Test-McpDestIsWorkspaceLocal -DestPath $DestPath)
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

function Invoke-JaqUtf8 {
    # Runs jaq and captures stdout as UTF-8 regardless of console codepage (CJK-safe).
    param([string[]]$JaqArgs)
    $prevEnc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $out = (& jaq @JaqArgs | Out-String)
    } finally {
        [Console]::OutputEncoding = $prevEnc
    }
    return @{ ExitCode = $LASTEXITCODE; Output = $out }
}

function Test-ClaudeGraphifyMcpInSync {
    # ~/.claude.json is Claude Code's live state file: huge, deeply nested, CJK text.
    # PowerShell 5.1 ConvertFrom-Json has a ~2MB limit and mangles DateTime strings,
    # so both the check and the merge must go through jaq only (byte-safe).
    param([string]$TemplatePath, [string]$DestPath)
    if (-not (Test-Path $TemplatePath)) { return $false }
    $template = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $want = New-MaterializedGraphifyServer -TemplateServer $template.mcpServers.graphify
    if (-not $want) { return $true }  # graphify-mcp not installed: nothing to enforce
    if (-not (Test-Path $DestPath)) { return $false }
    if (-not (Get-Command jaq -ErrorAction SilentlyContinue)) { return $false }

    $srvTmp = Join-Path $env:TEMP ("graphify_mcp_want_{0}.json" -f ([Guid]::NewGuid().ToString('N')))
    try {
        [System.IO.File]::WriteAllText($srvTmp, ($want | ConvertTo-Json -Depth 10 -Compress), [System.Text.UTF8Encoding]::new($false))
        $res = Invoke-JaqUtf8 -JaqArgs @('--slurpfile', 'w', $srvTmp, '(.mcpServers.graphify // null) == $w[0]', $DestPath)
        return ($res.ExitCode -eq 0 -and $res.Output.Trim() -eq 'true')
    } finally {
        Remove-Item $srvTmp -Force -ErrorAction SilentlyContinue
    }
}

function Merge-GraphifyMcpIntoClaudeUserConfig {
    param([string]$TemplatePath, [string]$DestPath)
    if (-not (Test-Path $TemplatePath)) {
        Write-Warning "[SKIP] MCP template missing: $TemplatePath"
        return
    }
    if (Test-ClaudeGraphifyMcpInSync -TemplatePath $TemplatePath -DestPath $DestPath) {
        Write-Host "  [OK] MCP graphify already in sync -> $DestPath" -ForegroundColor DarkGray
        $script:skippedCount++
        return
    }

    $template = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8).Trim() | ConvertFrom-Json
    $graphifyServer = New-MaterializedGraphifyServer -TemplateServer $template.mcpServers.graphify
    if (-not $graphifyServer) {
        Write-Warning "[SKIP] graphify-mcp not found; Claude Code MCP merge skipped. Run scripts/03_setup_runtimes.ps1 then re-run sync-rules."
        return
    }
    if (-not (Get-Command jaq -ErrorAction SilentlyContinue)) {
        Write-Warning "[SKIP] jaq not found; cannot surgically merge $DestPath."
        return
    }

    if (-not (Test-Path $DestPath)) {
        [System.IO.File]::WriteAllText($DestPath, "{}`n", [System.Text.UTF8Encoding]::new($false))
    }

    $srvTmp = Join-Path $env:TEMP ("graphify_mcp_server_{0}.json" -f ([Guid]::NewGuid().ToString('N')))
    $outTmp = "$DestPath.graphify-merge.tmp"
    try {
        [System.IO.File]::WriteAllText($srvTmp, ($graphifyServer | ConvertTo-Json -Depth 10 -Compress), [System.Text.UTF8Encoding]::new($false))

        $res = Invoke-JaqUtf8 -JaqArgs @('-c', '--slurpfile', 'g', $srvTmp, '.mcpServers = ((.mcpServers // {}) + {graphify: ($g[0])})', $DestPath)
        if ($res.ExitCode -ne 0 -or -not $res.Output.Trim()) {
            Write-Warning "[FAIL] jaq merge failed for $DestPath (exit $($res.ExitCode)); file left untouched."
            return
        }

        # Validate merged output with jaq before replacing the live file (never trust a blind write).
        # NOTE: the filter must not contain double quotes (PS 5.1 native arg passing mangles them).
        [System.IO.File]::WriteAllText($outTmp, $res.Output.Trim() + "`n", [System.Text.UTF8Encoding]::new($false))
        $check = Invoke-JaqUtf8 -JaqArgs @('-r', '.mcpServers.graphify.command // empty', $outTmp)
        if ($check.ExitCode -ne 0 -or -not $check.Output.Trim()) {
            Write-Warning "[FAIL] merged JSON validation failed for $DestPath; file left untouched."
            return
        }

        Move-Item -Path $outTmp -Destination $DestPath -Force
        Write-Host "  [SYNCED] MCP graphify (surgical jaq merge) -> $DestPath" -ForegroundColor Green
        $script:syncedCount++
    } finally {
        Remove-Item $srvTmp -Force -ErrorAction SilentlyContinue
        if (Test-Path $outTmp) { Remove-Item $outTmp -Force -ErrorAction SilentlyContinue }
    }
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

$projectClaudeMd = Join-Path $rootDir "CLAUDE.md"

$allTargets = @(
    @{ Name = "Antigravity Global Rules";            Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config") "AGENTS.md"; IsDir = $false },
    @{ Name = "Claude Code Global Rules";            Src = $masterRules; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude") "CLAUDE.md";        IsDir = $false },
    @{ Name = "Cursor Global Rules";                 Src = $masterRules; Dest = Join-Path (Join-Path $env:APPDATA "Cursor\User") "AGENTS.md";       IsDir = $false },
    @{ Name = "Antigravity Global Modern-CLI";       Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "modern-cli-expert"; IsDir = $true },
    @{ Name = "Claude Code Global Modern-CLI";       Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Cursor Global Modern-CLI";            Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Agents Skills Modern-CLI";            Src = $masterModernCliDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "modern-cli-expert";        IsDir = $true },
    @{ Name = "Antigravity Global Browser-Agent";    Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "browser-agent"; IsDir = $true },
    @{ Name = "Claude Code Global Browser-Agent";    Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "browser-agent";        IsDir = $true },
    @{ Name = "Cursor Global Browser-Agent";         Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "browser-agent";        IsDir = $true },
    @{ Name = "Agents Skills Browser-Agent";         Src = $masterBrowserAgentDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "browser-agent";        IsDir = $true },
    @{ Name = "Antigravity Global Graphify-Nav";     Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "graphify-navigator"; IsDir = $true },
    @{ Name = "Claude Code Global Graphify-Nav";     Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "graphify-navigator";        IsDir = $true },
    @{ Name = "Cursor Global Graphify-Nav";          Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "graphify-navigator";        IsDir = $true },
    @{ Name = "Agents Skills Graphify-Nav";          Src = $masterGraphifyNavDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "graphify-navigator";        IsDir = $true },
    @{ Name = "Antigravity Global Graphify-Builder"; Src = $masterGraphifyBuilderDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "graphify-builder"; IsDir = $true },
    @{ Name = "Claude Code Global Graphify-Builder"; Src = $masterGraphifyBuilderDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "graphify-builder";        IsDir = $true },
    @{ Name = "Cursor Global Graphify-Builder";      Src = $masterGraphifyBuilderDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "graphify-builder";        IsDir = $true },
    @{ Name = "Agents Skills Graphify-Builder";      Src = $masterGraphifyBuilderDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "graphify-builder";        IsDir = $true },
    @{ Name = "Antigravity Global RTK-Expert";       Src = $masterRtkExpertDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\skills") "rtk-expert";           IsDir = $true },
    @{ Name = "Claude Code Global RTK-Expert";       Src = $masterRtkExpertDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\skills") "rtk-expert";                  IsDir = $true },
    @{ Name = "Cursor Global RTK-Expert";            Src = $masterRtkExpertDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\skills") "rtk-expert";                  IsDir = $true },
    @{ Name = "Agents Skills RTK-Expert";            Src = $masterRtkExpertDir; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\skills") "rtk-expert";                  IsDir = $true },
    @{ Name = "RTK Global Config (AppData)";        Src = $masterRtkConfig; Dest = Join-Path (Join-Path $env:APPDATA "rtk") "config.toml";                                     IsDir = $false },
    @{ Name = "RTK User Config (.config)";           Src = $masterRtkConfig; Dest = Join-Path (Join-Path (Join-Path $env:USERPROFILE ".config") "rtk") "config.toml";            IsDir = $false },
    @{ Name = "Claude Code Global Settings";         Src = $masterClaudeSettings; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude") "settings.json";                        IsDir = $false; GuardPath = Join-Path (Join-Path $env:USERPROFILE ".claude\scripts") "agent_guard.py" },
    @{ Name = "Antigravity Global Graphify Rule";    Src = (Join-Path $masterAntigravityDir "rules\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\rules") "graphify.md"; IsDir = $false },
    @{ Name = "Antigravity Global Edit Orchestration"; Src = (Join-Path $masterAntigravityDir "rules\edit-orchestration.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\rules") "edit-orchestration.md"; IsDir = $false },
    @{ Name = "Antigravity Global Graphify Workflow";Src = (Join-Path $masterAntigravityDir "workflows\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\workflows") "graphify.md"; IsDir = $false },
    @{ Name = "Agents Always-on Graphify Rule";      Src = (Join-Path $masterAntigravityDir "rules\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\rules") "graphify.md"; IsDir = $false },
    @{ Name = "Agents Always-on Edit Orchestration"; Src = (Join-Path $masterAntigravityDir "rules\edit-orchestration.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\rules") "edit-orchestration.md"; IsDir = $false },
    @{ Name = "Agents Graphify Workflow";            Src = (Join-Path $masterAntigravityDir "workflows\graphify.md"); Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\workflows") "graphify.md"; IsDir = $false },
    @{ Name = "Cursor Always-on Graphify Rule";      Src = (Join-Path $masterCursorRulesDir "graphify.mdc"); Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\rules") "graphify.mdc"; IsDir = $false },
    @{ Name = "Antigravity Global Hooks";            Src = $masterHooks; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config") "hooks.json"; IsDir = $false; GuardPath = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\scripts") "agent_guard.py" },
    @{ Name = "Workspace Agent Hooks";               Src = $masterHooks; Dest = Join-Path (Join-Path $rootDir ".agents") "hooks.json"; IsDir = $false; GuardPath = Join-Path (Join-Path $rootDir ".agents\scripts") "agent_guard.py" },
    @{ Name = "Global Agents Hooks";                  Src = $masterHooks; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents") "hooks.json"; IsDir = $false; GuardPath = Join-Path (Join-Path $env:USERPROFILE ".agents\scripts") "agent_guard.py" },
    @{ Name = "Cursor Global Hooks";                 Src = $masterCursorHooks; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor") "hooks.json"; IsDir = $false; GuardPath = Join-Path (Join-Path $env:USERPROFILE ".cursor\scripts") "agent_guard.py" },
    @{ Name = "Workspace Cursor Hooks";              Src = $masterCursorHooks; Dest = Join-Path (Join-Path $rootDir ".cursor") "hooks.json"; IsDir = $false; GuardPath = $masterAgentGuard },
    @{ Name = "Antigravity Global Agent Guard";      Src = $masterAgentGuard; Dest = Join-Path (Join-Path $env:USERPROFILE ".gemini\config\scripts") "agent_guard.py"; IsDir = $false },
    @{ Name = "Global Agents Guard";                 Src = $masterAgentGuard; Dest = Join-Path (Join-Path $env:USERPROFILE ".agents\scripts") "agent_guard.py"; IsDir = $false },
    @{ Name = "Cursor Global Agent Guard";           Src = $masterAgentGuard; Dest = Join-Path (Join-Path $env:USERPROFILE ".cursor\scripts") "agent_guard.py"; IsDir = $false },
    @{ Name = "Claude Global Agent Guard";           Src = $masterAgentGuard; Dest = Join-Path (Join-Path $env:USERPROFILE ".claude\scripts") "agent_guard.py"; IsDir = $false },
    @{ Name = "Workspace Agent Guard";               Src = $masterAgentGuard; Dest = Join-Path (Join-Path $rootDir ".agents\scripts") "agent_guard.py"; IsDir = $false },
    @{ Name = "Workspace Claude Pointer (CLAUDE.md)"; Src = $masterClaudeProjectPointer; Dest = $projectClaudeMd; IsDir = $false }
)

# Broad vendor "graphify" skills conflict with SSOT graphify-navigator.
$vendorGraphifySkillDirs = @(
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
)

foreach ($target in $allTargets) {
    if (-not (Test-Path $target.Src)) {
        Write-Warning "[MISSING] Source missing: $($target.Src)"
        $hasDiff = $true
        continue
    }

    $generatedContent = $null
    if ($target.GuardPath) {
        $generatedContent = Get-HookContentWithGuardPath -SrcFile $target.Src -GuardPath $target.GuardPath
    }

    $isIdentical = $false
    if ($target.IsDir) {
        $isIdentical = Test-DirectoriesIdentical -SrcDir $target.Src -DestDir $target.Dest
    } elseif ($null -ne $generatedContent) {
        $isIdentical = Test-TextContentIdentical -Content $generatedContent -File $target.Dest
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
                if ($null -ne $generatedContent) {
                    [System.IO.File]::WriteAllText($target.Dest, $generatedContent, [System.Text.UTF8Encoding]::new($false))
                } else {
                    Copy-Item -Path $target.Src -Destination $target.Dest -Force
                }
            }
            Write-Host "  [SYNCED] $($target.Name) -> $($target.Dest)" -ForegroundColor Green
            $syncedCount++
        }
    }
}

$mcpTargets = @(
    (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json")
    (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
    (Join-Path $env:USERPROFILE ".agents\mcp_config.json")
    (Join-Path $env:USERPROFILE ".cursor\mcp.json")
    (Join-Path $rootDir ".agents\mcp_config.json")
    (Join-Path $rootDir ".cursor\mcp.json")
)

Write-Host "`n>> Graphify MCP (merge; absolute exe; workspace graph pin / global unpinned)..." -ForegroundColor Cyan
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

# Claude Code user scope (~/.claude.json): surgical jaq merge only (never PS JSON round-trip).
$claudeUserConfig = Join-Path $env:USERPROFILE ".claude.json"
Write-Host "`n>> Graphify MCP for Claude Code (~/.claude.json; surgical jaq merge)..." -ForegroundColor Cyan
if ($Check) {
    if (Test-ClaudeGraphifyMcpInSync -TemplatePath $mcpTemplate -DestPath $claudeUserConfig) {
        Write-Host "  [OK] MCP graphify in sync -> $claudeUserConfig" -ForegroundColor DarkGray
        $skippedCount++
    } else {
        Write-Host "  [DIFF] MCP graphify differs or missing -> $claudeUserConfig" -ForegroundColor Yellow
        $hasDiff = $true
    }
} else {
    Merge-GraphifyMcpIntoClaudeUserConfig -TemplatePath $mcpTemplate -DestPath $claudeUserConfig
}

# Duplicated always-on mirrors bloat every agent turn and dilute instruction priority.
# Cursor reads AGENTS.md natively; the global ~/.cursor/rules/graphify.mdc covers this machine.
$staleWorkspaceMirrors = @(
    (Join-Path $rootDir ".cursorrules")
    (Join-Path $rootDir ".cursor\rules\graphify.mdc")
)
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
}
