#Requires -Version 5.1
<#
.SYNOPSIS
    dotfiles-windows および AI Agent 高速化・安定化環境の網羅的自動テストスクリプト
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# UTF-8 出力エンコーディング
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# PATHの再読み込み
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

$rootDir = Split-Path -Parent $PSScriptRoot
$psExe = "powershell.exe"
$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($pwshCmd) { $psExe = $pwshCmd.Source }
$passedCount = 0
$failedCount = 0
$warnCount   = 0

function Assert-Test {
    param (
        [string]$Name,
        [bool]$Condition,
        [string]$Details = ""
    )
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passedCount++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkRed }
        $script:failedCount++
    }
}

function Get-McpArgList {
    param($Server)
    if (-not $Server) { return @() }
    $a = $Server.args
    if ($null -eq $a) { return @() }
    return @($a | ForEach-Object { [string]$_ })
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "  AI Agent & Modern CLI Environment Verification Suite " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# --- 1. CLI Tools Executability ---
Write-Host "`n[1/5] Checking Modern CLI Executables..." -ForegroundColor White

$toolsToCheck = @(
    @{ Cmd = "rg";       Name = "ripgrep (rg)";       Args = "--version" }
    @{ Cmd = "fd";       Name = "fd";                 Args = "--version" }
    @{ Cmd = "bat";      Name = "bat";                Args = "--version" }
    @{ Cmd = "eza";      Name = "eza";                Args = "--version" }
    @{ Cmd = "sd";       Name = "sd";                 Args = "--version" }
    @{ Cmd = "ast-grep"; Name = "ast-grep";           Args = "--version" }
    @{ Cmd = "jq";       Name = "jq";                 Args = "--version" }
    @{ Cmd = "delta";    Name = "delta";              Args = "--version" }
    @{ Cmd = "just";     Name = "just";               Args = "--version" }
    @{ Cmd = "nu";       Name = "Nushell (nu)";       Args = "--version" }
    @{ Cmd = "pwsh";     Name = "PowerShell 7 (pwsh)";Args = "--version" }
    @{ Cmd = "head";     Name = "uutils (head)";      Args = "--version" }
    @{ Cmd = "tail";     Name = "uutils (tail)";      Args = "--version" }
    @{ Cmd = "wc";       Name = "uutils (wc)";        Args = "--version" }
    @{ Cmd = "difft";    Name = "difftastic (difft)"; Args = "--version" }
    @{ Cmd = "xh";       Name = "xh (HTTP client)";   Args = "--version" }
    @{ Cmd = "procs";    Name = "procs (ps viewer)";  Args = "--version" }
    @{ Cmd = "jaq";      Name = "jaq (Rust jq)";      Args = "--version" }
    @{ Cmd = "rtk";      Name = "rtk (Rust Token Killer)"; Args = "--version" }
    @{ Cmd = "hexyl";    Name = "hexyl (hex viewer)"; Args = "--version" }
    @{ Cmd = "glow";         Name = "glow (Markdown)";    Args = "--version" }
    @{ Cmd = "chafa";        Name = "chafa (Sixel/Image)";Args = "--version" }
    @{ Cmd = "herdr";        Name = "Herdr (AI TUI)";     Args = "--version" }
    @{ Cmd = "cursor-agent"; Name = "Cursor Agent CLI";   Args = "--version" }
    @{ Cmd = "agent";        Name = "Cursor Agent Alias"; Args = "--version" }
    @{ Cmd = "fnm";          Name = "fnm (Node Manager)"; Args = "--version" }
    @{ Cmd = "node";         Name = "Node.js (node)";     Args = "--version" }
    @{ Cmd = "npm";          Name = "npm";                Args = "--version" }
    @{ Cmd = "npx";          Name = "npx (Package Runner)"; Args = "--version" }
    @{ Cmd = "pnpm";         Name = "pnpm";               Args = "--version" }
)

foreach ($tool in $toolsToCheck) {
    $found = Get-Command $tool.Cmd -ErrorAction SilentlyContinue
    if ($found) {
        try {
            $output = & $tool.Cmd ($tool.Args -split " ") 2>&1 | Out-String
            $valid = ($output.Length -gt 0)
            Assert-Test -Name "$($tool.Name) is executable" -Condition $valid -Details "Path: $($found.Source)"
        } catch {
            Assert-Test -Name "$($tool.Name) is executable" -Condition $false -Details "$_"
        }
    } else {
        Assert-Test -Name "$($tool.Name) is installed in PATH" -Condition $false -Details "Command not found: $($tool.Cmd)"
    }
}

# Herdr Plugin (herdr-sidebar) Verification
if (Get-Command herdr -ErrorAction SilentlyContinue) {
    try {
        $pList = herdr plugin list 2>&1 | Out-String
        $hasSidebar = $pList -match "herdr-sidebar"
        Assert-Test -Name "Herdr plugin: herdr-sidebar is installed and enabled" -Condition $hasSidebar -Details ($pList.Trim())
    } catch {
        Assert-Test -Name "Herdr plugin: herdr-sidebar is installed and enabled" -Condition $false -Details "$_"
    }
}

# --- 2. AI Agent Safety Environment Variables ---
Write-Host "`n[2/5] Checking AI Agent Safety Environment Variables..." -ForegroundColor White

$envChecks = @(
    @{ Var = "PAGER";                       Expected = "cat" }
    @{ Var = "BAT_STYLE";                   Expected = "plain" }
    @{ Var = "GIT_PAGER";                   Expected = "cat" }
    @{ Var = "DELTA_PAGER";                 Expected = "cat" }
    @{ Var = "PYTHONUTF8";                  Expected = "1" }
    @{ Var = "POWERSHELL_TELEMETRY_OPTOUT"; Expected = "1" }
)

foreach ($ec in $envChecks) {
    $userVal = [System.Environment]::GetEnvironmentVariable($ec.Var, "User")
    $currentVal = (Get-Item -Path "env:$($ec.Var)" -ErrorAction SilentlyContinue).Value
    $isOk = ($userVal -eq $ec.Expected -or $currentVal -eq $ec.Expected)
    Assert-Test -Name "EnvVar: $($ec.Var) == '$($ec.Expected)'" -Condition $isOk -Details "Current: '$currentVal', UserScope: '$userVal'"
}

# BAT_PAGER is safe when either empty string or not invoking pager
$batPagerUser = [System.Environment]::GetEnvironmentVariable("BAT_PAGER", "User")
$batPagerCurr = (Get-Item -Path "env:BAT_PAGER" -ErrorAction SilentlyContinue).Value
$batPagerOk = ([string]::IsNullOrEmpty($batPagerUser) -or $batPagerUser -eq "") -and ([string]::IsNullOrEmpty($batPagerCurr) -or $batPagerCurr -eq "")
Assert-Test -Name "EnvVar: BAT_PAGER is empty/disabled" -Condition $batPagerOk -Details "User: '$batPagerUser', Current: '$batPagerCurr'"

# --- 3. Configuration & SSOT Rules Deployment ---
Write-Host "`n[3/5] Checking AI Agent SSOT Rules & Dotfiles Deployment..." -ForegroundColor White

$configFiles = @(
    # Workspace Level Files (for instant agent context)
    @{ Name = "Workspace Project Guide (AGENTS.md)";         Path = Join-Path $rootDir "AGENTS.md" }

    # Master SSOT Configs
    @{ Name = "Master SSOT Rules (configs/agents/GLOBAL_RULES.md)"; Path = Join-Path $rootDir "configs\agents\GLOBAL_RULES.md" }
    @{ Name = "Master modern-cli Skill";                     Path = Join-Path $rootDir "configs\agents\skills\modern-cli-expert\SKILL.md" }
    @{ Name = "Master browser-agent Skill";                  Path = Join-Path $rootDir "configs\agents\skills\browser-agent\SKILL.md" }
    @{ Name = "Master tui-wireframe-designer Skill";         Path = Join-Path $rootDir "configs\agents\skills\tui-wireframe-designer\SKILL.md" }
    @{ Name = "Master RTK config";                           Path = Join-Path $rootDir "configs\rtk\config.toml" }
    @{ Name = "Master Cursor MCP template";                  Path = Join-Path $rootDir "configs\agents\cursor\mcp_config.json" }
    @{ Name = "Master pins.json";                            Path = Join-Path $rootDir "configs\pins.json" }

    # Global Deployed Targets (Cursor-only)
    @{ Name = "Cursor Global Rules";                         Path = Join-Path $env:APPDATA "Cursor\User\AGENTS.md" }
    @{ Name = "Cursor Global Skill (modern-cli)";            Path = Join-Path $env:USERPROFILE ".cursor\skills\modern-cli-expert\SKILL.md" }
    @{ Name = "Cursor Global Skill (browser-agent)";         Path = Join-Path $env:USERPROFILE ".cursor\skills\browser-agent\SKILL.md" }
    @{ Name = "Cursor Global Skill (tui-wireframe)";         Path = Join-Path $env:USERPROFILE ".cursor\skills\tui-wireframe-designer\SKILL.md" }
    @{ Name = "RTK AppData config";                          Path = Join-Path $env:APPDATA "rtk\config.toml" }
    @{ Name = "Nushell config.nu";                           Path = Join-Path $env:APPDATA "nushell\config.nu" }
    @{ Name = "Nushell env.nu";                              Path = Join-Path $env:APPDATA "nushell\env.nu" }
    @{ Name = "PowerShell 5.1 Profile";                      Path = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell") "Microsoft.PowerShell_profile.ps1" }
    @{ Name = "PowerShell 7 Profile";                        Path = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell") "Microsoft.PowerShell_profile.ps1" }
    @{ Name = "Script: setup_api_keys.ps1";                  Path = Join-Path $rootDir "scripts\setup_api_keys.ps1" }
    @{ Name = "Script: audit_workspace.ps1";                 Path = Join-Path $rootDir "scripts\audit_workspace.ps1" }
    @{ Name = "Script: Assert-PinnedHash.ps1";               Path = Join-Path $rootDir "scripts\Assert-PinnedHash.ps1" }
    @{ Name = "Test: verify_security.ps1";                   Path = Join-Path $rootDir "tests\verify_security.ps1" }
    @{ Name = "Cursor Global hooks";                         Path = Join-Path $env:USERPROFILE ".cursor\hooks.json" }
)

foreach ($cf in $configFiles) {
    $exists = Test-Path $cf.Path
    Assert-Test -Name "Config: $($cf.Name) exists" -Condition $exists -Details "Path: $($cf.Path)"
}

# Verify SSOT Rules Compactness (prevents prompt bloat; always-on layers must stay lean)
$masterRulesFile = Join-Path $rootDir "configs\agents\GLOBAL_RULES.md"
if (Test-Path $masterRulesFile) {
    $rulesLineCount = (Get-Content $masterRulesFile | Measure-Object -Line).Lines
    Assert-Test -Name "SSOT Rules Compactness (GLOBAL_RULES.md < 100 lines)" -Condition ($rulesLineCount -lt 100) -Details "Current lines: $rulesLineCount"
}
$projectAgentsFile = Join-Path $rootDir "AGENTS.md"
if (Test-Path $projectAgentsFile) {
    $agentsLineCount = (Get-Content $projectAgentsFile | Measure-Object -Line).Lines
    Assert-Test -Name "Project Guide Compactness (AGENTS.md < 100 lines)" -Condition ($agentsLineCount -lt 100) -Details "Current lines: $agentsLineCount"

    # Verify AGENTS.md scripts map exactness (no shorthand or phantom filenames)
    $agentsRaw = Get-Content -Raw -Path $projectAgentsFile
    if ($agentsRaw -match 'scripts/\s+([^\r\n]+)') {
        $scriptNames = $Matches[1] -split ',\s*'
        $missingScripts = @()
        foreach ($s in $scriptNames) {
            $sClean = $s.Trim()
            if ($sClean -and -not (Test-Path (Join-Path $rootDir "scripts\$sClean"))) {
                $missingScripts += $sClean
            }
        }
        Assert-Test -Name "AGENTS.md scripts map has zero phantom / shorthand files" -Condition ($missingScripts.Count -eq 0) -Details ("Missing: " + ($missingScripts -join ", "))
    }
}

# Official Cursor rtk hook (user ~/.cursor/hooks.json). SSOT must not ship a competing wall.
Assert-Test -Name "Master does not ship configs/agents/cursor/hooks.json" -Condition (-not (Test-Path (Join-Path $rootDir "configs\agents\cursor\hooks.json")))
Assert-Test -Name "Master does not ship configs/agents/cursor/hooks.global.json" -Condition (-not (Test-Path (Join-Path $rootDir "configs\agents\cursor\hooks.global.json")))
Assert-Test -Name "Master does not ship scripts/agent_guard.py" -Condition (-not (Test-Path (Join-Path $rootDir "scripts\agent_guard.py")))
Assert-Test -Name "Master does not ship scripts/graphify_semantic.py" -Condition (-not (Test-Path (Join-Path $rootDir "scripts\graphify_semantic.py")))
Assert-Test -Name "Master does not ship tests/verify_semantic_harness.ps1" -Condition (-not (Test-Path (Join-Path $rootDir "tests\verify_semantic_harness.ps1")))
Assert-Test -Name "Master does not ship graphify-navigator skill" -Condition (-not (Test-Path (Join-Path $rootDir "configs\agents\skills\graphify-navigator")))
Assert-Test -Name "Master does not ship graphify-builder skill" -Condition (-not (Test-Path (Join-Path $rootDir "configs\agents\skills\graphify-builder")))
Assert-Test -Name "Master does not ship impeccable-agile skill" -Condition (-not (Test-Path (Join-Path $rootDir "configs\agents\skills\impeccable-agile")))
Assert-Test -Name "graphify CLI is not on PATH" -Condition ($null -eq (Get-Command graphify -ErrorAction SilentlyContinue))
Assert-Test -Name "graphify-mcp CLI is not on PATH" -Condition ($null -eq (Get-Command graphify-mcp -ErrorAction SilentlyContinue))
Assert-Test -Name "Workspace .cursor/hooks.json is absent" -Condition (-not (Test-Path (Join-Path $rootDir ".cursor\hooks.json")))
$userHooks = Join-Path $env:USERPROFILE ".cursor\hooks.json"
if (Test-Path $userHooks) {
    $uh = Get-Content -Raw -Path $userHooks
    Assert-Test -Name "User ~/.cursor/hooks.json contains rtk hook cursor" -Condition ($uh -match 'rtk hook cursor') -Details $userHooks
    Assert-Test -Name "User ~/.cursor/hooks.json has no agent_guard" -Condition ($uh -notmatch 'agent_guard') -Details $userHooks
} else {
    Assert-Test -Name "User ~/.cursor/hooks.json exists" -Condition $false -Details "Run: rtk init -g --agent cursor --hook-only --auto-patch"
}
$rtkCheck = (& rtk hook check "git status" 2>&1 | Out-String).Trim()
Assert-Test -Name "rtk hook check rewrites git status" -Condition ($rtkCheck -match 'rtk git status') -Details $rtkCheck

# Anti-duplication invariants: duplicated always-on mirrors double-load context every turn.
Assert-Test -Name "No duplicated workspace .cursorrules (Cursor reads AGENTS.md natively)" -Condition (-not (Test-Path (Join-Path $rootDir ".cursorrules"))) -Details "Remove it: just sync-rules"
Assert-Test -Name "No duplicated workspace .cursor/rules/graphify.mdc (AGENTS.md is the protocol)" -Condition (-not (Test-Path (Join-Path $rootDir ".cursor\rules\graphify.mdc"))) -Details "Remove it: just sync-rules"
Assert-Test -Name "No global always-on graphify.mdc (would tax every workspace)" -Condition (-not (Test-Path (Join-Path $env:USERPROFILE ".cursor\rules\graphify.mdc"))) -Details "Remove it: just sync-rules"
$agentsRoot = Join-Path $rootDir "configs\agents"
$allowedAgents = @("cursor", "skills", "GLOBAL_RULES.md")
$extraAgents = @(Get-ChildItem -Path $agentsRoot -Force | Where-Object { $allowedAgents -notcontains $_.Name } | ForEach-Object { $_.Name })
Assert-Test -Name "configs/agents contains only Cursor SSOT entries" -Condition ($extraAgents.Count -eq 0) -Details ("Extra: " + ($extraAgents -join ", "))

$justfileText = Get-Content -Raw -Path (Join-Path $rootDir "justfile")
Assert-Test -Name "justfile windows-shell is powershell.exe (5.1 bootstrap trampoline)" -Condition ($justfileText -match 'windows-shell := \["powershell\.exe"') -Details "just install must run before pwsh exists"
Assert-Test -Name "justfile install recipe uses powershell.exe" -Condition ($justfileText -match '(?m)^install:\r?\n\s+@powershell\.exe') -Details "just install is the 5.1 bootstrap"
Assert-Test -Name "justfile test/audit recipes use pwsh.exe" -Condition ($justfileText -match '(?m)^test:\r?\n\s+@pwsh\.exe' -and $justfileText -match '(?m)^audit:\r?\n\s+@pwsh\.exe') -Details "post-install recipes host PowerShell 7"

$allowedRootMd = @("AGENTS.md", "README.md")
$extraRootMd = @(Get-ChildItem -Path $rootDir -File -Filter "*.md" | Where-Object { $allowedRootMd -notcontains $_.Name } | ForEach-Object { $_.Name })
Assert-Test -Name "Repo root markdown is only AGENTS.md and README.md" -Condition ($extraRootMd.Count -eq 0) -Details ("Extra: " + ($extraRootMd -join ", "))

# Verify all PowerShell scripts parse cleanly in PowerShell AST and have UTF-8 BOM if non-ASCII
$allPsScripts = Get-ChildItem -Path (Join-Path $rootDir "scripts"), (Join-Path $rootDir "tests") -Filter "*.ps1" -File
foreach ($psScript in $allPsScripts) {
    $parseErrors = $null
    $parseTokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($psScript.FullName, [ref]$parseTokens, [ref]$parseErrors)
    $parseOk = ($parseErrors.Count -eq 0)
    $errDetail = if ($parseOk) { "Parsed successfully" } else { ($parseErrors | ForEach-Object { $_.Message }) -join "; " }
    Assert-Test -Name "PS Script AST parse: $($psScript.Name)" -Condition $parseOk -Details $errDetail

    $bytes = [System.IO.File]::ReadAllBytes($psScript.FullName)
    $hasNonAscii = ($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $bomOk = (-not $hasNonAscii) -or $hasBom
    $bomDetail = if ($hasBom) { "UTF-8 with BOM" } elseif (-not $hasNonAscii) { "ASCII only (no BOM needed)" } else { "Missing UTF-8 BOM on non-ASCII script" }
    Assert-Test -Name "PS Script UTF-8 BOM: $($psScript.Name)" -Condition $bomOk -Details $bomDetail
}



# leftover mcpServers.graphify must stay absent.
$mcpGlobalPaths = @(
    (Join-Path $env:USERPROFILE ".cursor\mcp.json")
)
$mcpWorkspacePaths = @(
    (Join-Path $rootDir ".cursor\mcp.json")
)

# Graphify MCP is not deployed. leftover mcpServers.graphify must stay absent.
function Assert-GraphifyMcpAbsent {
    param([string]$McpPath)
    $label = [IO.Path]::GetFileName($McpPath)
    if (-not (Test-Path $McpPath)) {
        Assert-Test -Name "MCP has no graphify ($label)" -Condition $true -Details "file absent"
        return
    }
    try {
        $mcpObj = [System.IO.File]::ReadAllText($McpPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $has = $false
        if ($mcpObj.mcpServers -and $mcpObj.mcpServers.PSObject.Properties['graphify']) { $has = $true }
        Assert-Test -Name "MCP has no graphify ($label)" -Condition (-not $has) -Details $McpPath
    } catch {
        Assert-Test -Name "MCP graphify config parse ($McpPath)" -Condition $false -Details "$_"
    }
}

foreach ($mcpPath in $mcpGlobalPaths) {
    Assert-GraphifyMcpAbsent -McpPath $mcpPath
}
foreach ($mcpPath in $mcpWorkspacePaths) {
    Assert-GraphifyMcpAbsent -McpPath $mcpPath
}

# Pin checks: rtk version must match configs/pins.json
function Get-PinsJson {
    $pinsPath = Join-Path $rootDir "configs\pins.json"
    $jaqCmd = Get-Command jaq -ErrorAction SilentlyContinue
    if ($jaqCmd) {
        $raw = (& jaq -c '.' $pinsPath 2>&1 | Out-String).Trim()
        if ($raw) {
            try { return $raw | ConvertFrom-Json } catch { }
        }
    }
    return (Get-Content -Raw -Path $pinsPath | ConvertFrom-Json)
}

$pins = $null
try { $pins = Get-PinsJson } catch { $pins = $null }
Assert-Test -Name "configs/pins.json is readable" -Condition ($null -ne $pins) -Details "jaq/ConvertFrom-Json failed"
if ($pins) {
    $rtkPin = [string]$pins.rtk
    $rVer = if (Get-Command rtk -ErrorAction SilentlyContinue) { (& rtk --version 2>&1 | Out-String) } else { "" }
    Assert-Test -Name "rtk --version contains pin $rtkPin" -Condition ($rVer -match [regex]::Escape($rtkPin)) -Details ("version='$rVer'")
    $pinNames = @($pins.PSObject.Properties.Name)
    Assert-Test -Name "configs/pins.json has no graphifyy key" -Condition ($pinNames -notcontains 'graphifyy') -Details ($pinNames -join ', ')
}

# UDEV Gothic NF Font Check
$fontInstalled = $false
$checkFontFiles = @("UDEVGothicNF-Regular.ttf", "UDEVGothic35NF-Regular.ttf")
foreach ($ff in $checkFontFiles) {
    if ((Test-Path (Join-Path "$env:SystemRoot\Fonts" $ff)) -or (Test-Path (Join-Path "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" $ff))) {
        $fontInstalled = $true
        break
    }
}
Assert-Test -Name "Font: UDEV Gothic NF is installed" -Condition $fontInstalled -Details "Checked System and User Fonts"

# --- 4. Functional Execution & UTF-8 Tests ---
Write-Host "`n[4/5] Running Functional Integration & UTF-8 Tests..." -ForegroundColor White

$tempTestDir = Join-Path $env:TEMP "agent_env_test_$(Get-Random)"
New-Item -Path $tempTestDir -ItemType Directory -Force | Out-Null

try {
    # Test 4.1: UTF-8 Content with bat & rg
    $utf8File = Join-Path $tempTestDir "test_utf8.txt"
    $testKeyword = "UltraFastAgentTest"
    $fileBytes = [System.Text.Encoding]::UTF8.GetBytes("AI Agent Extreme Performance: $testKeyword`nJapanese: 高速安定性`nEnd of test line.")
    [System.IO.File]::WriteAllBytes($utf8File, $fileBytes)
    
    $rgResult = rg -n $testKeyword $utf8File 2>&1 | Out-String
    $rgOk = $rgResult -match $testKeyword
    Assert-Test -Name "rg UTF-8 search execution" -Condition $rgOk -Details $rgResult.Trim()

    # Test 4.2: Non-interactive bat file reading
    $batResult = bat --paging=never --style=plain $utf8File 2>&1 | Out-String
    $batOk = $batResult -match $testKeyword
    Assert-Test -Name "bat --paging=never non-interactive view" -Condition $batOk

    # Test 4.3: sd Regex In-Place Replacement
    sd "UltraFastAgentTest" "VerifiedAgentSuccess" $utf8File
    $replacedContent = [System.IO.File]::ReadAllText($utf8File, [System.Text.Encoding]::UTF8)
    $sdOk = $replacedContent -match "VerifiedAgentSuccess"
    Assert-Test -Name "sd in-place regex replacement" -Condition $sdOk

    # Test 4.4: jaq & jq JSON Processing (Deterministic UTF-8 without BOM)
    $jsonFile = Join-Path $tempTestDir "test.json"
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes('{"agent": "cursor", "speed": "extreme", "status": "active"}')
    [System.IO.File]::WriteAllBytes($jsonFile, $jsonBytes)
    $jaqCmd = Get-Command jaq -ErrorAction SilentlyContinue
    if ($jaqCmd) {
        $jaqResult = & jaq -r ".speed" $jsonFile 2>&1 | Out-String
        $jaqOk = ($jaqResult.Trim() -eq "extreme")
        Assert-Test -Name "jaq (Rust) stream JSON evaluation" -Condition $jaqOk
    } else {
        $jqResult = & jq -r ".speed" $jsonFile 2>&1 | Out-String
        $jqOk = ($jqResult.Trim() -eq "extreme")
        Assert-Test -Name "jq stream JSON evaluation" -Condition $jqOk
    }

    # Test 4.5: ast-grep AST Pattern Matching
    $jsFile = Join-Path $tempTestDir "test.js"
    [System.IO.File]::WriteAllText($jsFile, "function calculate(x) { return x * 2; }", [System.Text.Encoding]::UTF8)
    $astResult = ast-grep -p "function calculate(`$A) { `$`$`$B }" $jsFile 2>&1 | Out-String
    $astOk = $astResult -match "function calculate"
    Assert-Test -Name "ast-grep AST pattern match" -Condition $astOk

    # Test 4.6: Mermaid ASCII Diagram Rendering
    $mmdResult = nu -c "''graph TD`n  A[Client] --> B[Server]'' | ^bunx --bun mermaid-ascii" 2>&1 | Out-String
    $mmdOk = $mmdResult -match "Client" -and $mmdResult -match "Server"
    Assert-Test -Name "Mermaid ASCII diagram rendering" -Condition $mmdOk -Details ($mmdResult.Trim())

    # Test 4.7: AI Agent SSOT Rule Synchronization
    $syncCheckProc = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $rootDir "scripts\sync_agent_rules.ps1"), "-Check" -NoNewWindow -Wait -PassThru
    Assert-Test -Name "AI Agent SSOT Rule Synchronization (Master vs Targets)" -Condition ($syncCheckProc.ExitCode -eq 0) -Details "ExitCode: $($syncCheckProc.ExitCode)"

    # RTK Token Killer evaluation
    $rtkCmd = Get-Command rtk -ErrorAction SilentlyContinue
    if ($rtkCmd) {
        $rtkGainProc = Start-Process -FilePath "rtk.exe" -ArgumentList "gain" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\rtk_gain_test.txt" -RedirectStandardError "$env:TEMP\rtk_gain_err.txt"
        $rtkOk = ($rtkGainProc.ExitCode -eq 0)
        $rtkDetail = if (Test-Path "$env:TEMP\rtk_gain_test.txt") { (Get-Content "$env:TEMP\rtk_gain_test.txt" -Raw).Trim() } else { "rtk gain executed" }
        Remove-Item "$env:TEMP\rtk_gain_test.txt", "$env:TEMP\rtk_gain_err.txt" -Force -ErrorAction SilentlyContinue
        Assert-Test -Name "RTK (Rust Token Killer) gain metrics execution" -Condition $rtkOk -Details ($rtkDetail.Split("`n")[0])
    } else {
        Assert-Test -Name "RTK (Rust Token Killer) gain metrics execution" -Condition $false -Details "rtk command not found in PATH"
    }

} finally {
    Remove-Item -Path $tempTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 5. Performance Benchmark (rg vs Select-String across files) ---
Write-Host "`n[5/5] Performance Verification Benchmark (100,000 lines)..." -ForegroundColor White

$benchDir = Join-Path $env:TEMP "bench_$(Get-Random)"
New-Item -Path $benchDir -ItemType Directory -Force | Out-Null

try {
    # Generate 50 files with 2,000 lines each = 100,000 lines of data
    $chunk = ("Lorem ipsum dolor sit amet, consectetur adipiscing elit.`n" * 100)
    for ($i = 0; $i -lt 50; $i++) {
        $filePath = Join-Path $benchDir "file_$i.txt"
        $content = ($chunk * 20) + "TARGET_KEYWORD_UNIQUE_$i`n"
        [System.IO.File]::WriteAllText($filePath, $content, [System.Text.UTF8Encoding]::new($false))
    }

    # Warm-up OS filesystem cache once
    $null = rg "TARGET_KEYWORD_UNIQUE" $benchDir 2>&1

    $sw1 = [System.Diagnostics.Stopwatch]::StartNew()
    $rgMatches = rg "TARGET_KEYWORD_UNIQUE" $benchDir 2>&1
    $sw1.Stop()

    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    $psMatches = Get-ChildItem -Path $benchDir -Filter "*.txt" -Recurse | Select-String "TARGET_KEYWORD_UNIQUE"
    $sw2.Stop()

    Write-Host "  -> [Benchmark] rg execution time (all files):             $($sw1.ElapsedMilliseconds) ms" -ForegroundColor Cyan
    Write-Host "  -> [Benchmark] Select-String execution time (all files): $($sw2.ElapsedMilliseconds) ms" -ForegroundColor Gray
    
    $speedup = if ($sw1.ElapsedMilliseconds -gt 0) { [math]::Round($sw2.ElapsedMilliseconds / $sw1.ElapsedMilliseconds, 1) } else { 10 }
    Write-Host "  -> [Benchmark] Modern CLI Speedup: ~${speedup}x faster" -ForegroundColor Green
    Assert-Test -Name "Modern CLI search completed successfully ($($rgMatches.Count) matches)" -Condition ($rgMatches.Count -eq 50)
} finally {
    Remove-Item -Path $benchDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Final Summary ---
Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Test Summary: $passedCount PASSED, $failedCount FAILED, $warnCount WARNINGS" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
if ($failedCount -eq 0) {
    Write-Host " [GROUND TRUTH VERIFIED] All CLI tools, environment vars," -ForegroundColor Green
    Write-Host " dotfiles, PowerShell ASTs, and SSOT rules are 100% valid." -ForegroundColor Green
    Write-Host " No manual file inspection or terminal slicing needed." -ForegroundColor Green
}
Write-Host "=======================================================`n" -ForegroundColor Cyan

if ($failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
