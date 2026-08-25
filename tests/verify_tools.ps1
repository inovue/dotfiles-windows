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
    @{ Cmd = "graphify"; Name = "graphify (knowledge graph)"; Args = "hook status" }
    @{ Cmd = "graphify-mcp"; Name = "graphify-mcp (MCP server)"; Args = "--help" }
    @{ Cmd = "hexyl";    Name = "hexyl (hex viewer)"; Args = "--version" }
    @{ Cmd = "glow";         Name = "glow (Markdown)";    Args = "--version" }
    @{ Cmd = "chafa";        Name = "chafa (Sixel/Image)";Args = "--version" }
    @{ Cmd = "herdr";        Name = "Herdr (AI TUI)";     Args = "--version" }
    @{ Cmd = "cursor-agent"; Name = "Cursor Agent CLI";   Args = "--version" }
    @{ Cmd = "agent";        Name = "Cursor Agent Alias"; Args = "--version" }
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
    @{ Name = "Workspace Claude Guide (CLAUDE.md)";          Path = Join-Path $rootDir "CLAUDE.md" }
    @{ Name = "Workspace Cursor Rules (.cursorrules)";       Path = Join-Path $rootDir ".cursorrules" }

    # Master SSOT Configs
    @{ Name = "Master SSOT Rules (configs/agents/AGENTS.md)"; Path = Join-Path $rootDir "configs\agents\AGENTS.md" }
    @{ Name = "Master modern-cli Skill";                     Path = Join-Path $rootDir "configs\agents\skills\modern-cli-expert\SKILL.md" }
    @{ Name = "Master browser-agent Skill";                  Path = Join-Path $rootDir "configs\agents\skills\browser-agent\SKILL.md" }
    @{ Name = "Master graphify-navigator Skill";             Path = Join-Path $rootDir "configs\agents\skills\graphify-navigator\SKILL.md" }
    @{ Name = "Master Antigravity graphify rule";            Path = Join-Path $rootDir "configs\agents\antigravity\rules\graphify.md" }
    @{ Name = "Master Cursor graphify rule";                 Path = Join-Path $rootDir "configs\agents\cursor\rules\graphify.mdc" }
    @{ Name = "Master Antigravity MCP template";             Path = Join-Path $rootDir "configs\agents\antigravity\mcp_config.json" }

    # Global Deployed Targets
    @{ Name = "Antigravity Global Rules";                    Path = Join-Path $env:USERPROFILE ".gemini\config\AGENTS.md" }
    @{ Name = "Claude Code Global Rules";                    Path = Join-Path $env:USERPROFILE ".claude\CLAUDE.md" }
    @{ Name = "Cursor Global Rules";                         Path = Join-Path $env:APPDATA "Cursor\User\AGENTS.md" }
    @{ Name = "Antigravity Global Skill (modern-cli)";       Path = Join-Path $env:USERPROFILE ".gemini\config\skills\modern-cli-expert\SKILL.md" }
    @{ Name = "Claude Code Global Skill (modern-cli)";       Path = Join-Path $env:USERPROFILE ".claude\skills\modern-cli-expert\SKILL.md" }
    @{ Name = "Agents Global Skill (modern-cli)";            Path = Join-Path $env:USERPROFILE ".agents\skills\modern-cli-expert\SKILL.md" }
    @{ Name = "Antigravity Global Skill (browser-agent)";    Path = Join-Path $env:USERPROFILE ".gemini\config\skills\browser-agent\SKILL.md" }
    @{ Name = "Claude Code Global Skill (browser-agent)";    Path = Join-Path $env:USERPROFILE ".claude\skills\browser-agent\SKILL.md" }
    @{ Name = "Agents Global Skill (browser-agent)";         Path = Join-Path $env:USERPROFILE ".agents\skills\browser-agent\SKILL.md" }
    @{ Name = "Antigravity Global Skill (graphify-navigator)"; Path = Join-Path $env:USERPROFILE ".gemini\config\skills\graphify-navigator\SKILL.md" }
    @{ Name = "Claude Code Global Skill (graphify-navigator)"; Path = Join-Path $env:USERPROFILE ".claude\skills\graphify-navigator\SKILL.md" }
    @{ Name = "Agents Global Skill (graphify-navigator)";    Path = Join-Path $env:USERPROFILE ".agents\skills\graphify-navigator\SKILL.md" }
    @{ Name = "Antigravity Global Graphify Rule";            Path = Join-Path $env:USERPROFILE ".gemini\config\rules\graphify.md" }
    @{ Name = "Antigravity Global Graphify Workflow";        Path = Join-Path $env:USERPROFILE ".gemini\config\workflows\graphify.md" }
    @{ Name = "Cursor always-on graphify rule";              Path = Join-Path $env:USERPROFILE ".cursor\rules\graphify.mdc" }
    @{ Name = "Agents always-on graphify rule";              Path = Join-Path $env:USERPROFILE ".agents\rules\graphify.md" }
    @{ Name = "Agents graphify workflow";                    Path = Join-Path $env:USERPROFILE ".agents\workflows\graphify.md" }
    @{ Name = "Nushell config.nu";                           Path = Join-Path $env:APPDATA "nushell\config.nu" }
    @{ Name = "Nushell env.nu";                              Path = Join-Path $env:APPDATA "nushell\env.nu" }
    @{ Name = "PowerShell 5.1 Profile";                      Path = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell") "Microsoft.PowerShell_profile.ps1" }
    @{ Name = "PowerShell 7 Profile";                        Path = Join-Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) "PowerShell") "Microsoft.PowerShell_profile.ps1" }
    @{ Name = "Script: setup_api_keys.ps1";                  Path = Join-Path $rootDir "scripts\setup_api_keys.ps1" }
)

foreach ($cf in $configFiles) {
    $exists = Test-Path $cf.Path
    Assert-Test -Name "Config: $($cf.Name) exists" -Condition $exists -Details "Path: $($cf.Path)"
}

# Verify all PowerShell scripts parse cleanly in PowerShell AST (BOM & syntax check)
$allPsScripts = Get-ChildItem -Path (Join-Path $rootDir "scripts") -Filter "*.ps1" -File
foreach ($psScript in $allPsScripts) {
    $parseErrors = $null
    $parseTokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($psScript.FullName, [ref]$parseTokens, [ref]$parseErrors)
    $parseOk = ($parseErrors.Count -eq 0)
    $errDetail = if ($parseOk) { "Parsed successfully" } else { ($parseErrors | ForEach-Object { $_.Message }) -join "; " }
    Assert-Test -Name "PS Script AST parse: $($psScript.Name)" -Condition $parseOk -Details $errDetail
}


# MCP must use absolute graphify-mcp on all merge targets (uv tool run is ~8x slower and PATH-fragile)
$mcpPathsToCheck = @(
    (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json")
    (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
    (Join-Path $rootDir ".agents\mcp_config.json")
)
foreach ($mcpPath in $mcpPathsToCheck) {
    if (-not (Test-Path $mcpPath)) {
        # Missing dest is OK when graphify-mcp is not installed yet (sync skips merge)
        $graphifyMcpInstalled = $null -ne (Get-Command graphify-mcp -ErrorAction SilentlyContinue)
        if ($graphifyMcpInstalled) {
            Assert-Test -Name "MCP graphify config exists ($([IO.Path]::GetFileName($mcpPath)))" -Condition $false -Details "Missing: $mcpPath"
        } else {
            Write-Host "  [SKIP] MCP config absent (graphify-mcp not installed): $mcpPath" -ForegroundColor DarkGray
            $script:warnCount++
        }
        continue
    }
    try {
        $mcpObj = [System.IO.File]::ReadAllText($mcpPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if (-not $mcpObj.mcpServers -or -not $mcpObj.mcpServers.graphify) {
            $graphifyMcpInstalled = $null -ne (Get-Command graphify-mcp -ErrorAction SilentlyContinue)
            if ($graphifyMcpInstalled) {
                Assert-Test -Name "MCP graphify entry present ($([IO.Path]::GetFileName($mcpPath)))" -Condition $false -Details "No mcpServers.graphify in $mcpPath"
            }
            continue
        }
        $cmd = [string]$mcpObj.mcpServers.graphify.command
        $isAbs = ($cmd -match '(?i)\.exe$' -or $cmd -match '^[A-Za-z]:\\' -or $cmd -match '^/')
        $notUv = ($cmd -notmatch '(?i)(^|[\\/])uv(\.exe)?$')
        $notBare = ($cmd -ne "graphify-mcp" -and $cmd -ne "graphify-mcp.exe")
        $pathOk = if ($isAbs) { Test-Path $cmd } else { $false }
        Assert-Test -Name "MCP graphify uses absolute graphify-mcp ($([IO.Path]::GetFileName($mcpPath)))" -Condition ($isAbs -and $notUv -and $notBare -and $pathOk) -Details "command='$cmd'"
    } catch {
        Assert-Test -Name "MCP graphify config parse ($mcpPath)" -Condition $false -Details "$_"
    }
}

# UDEV Gothic NF Font Check
$fontInstalled = $false
$checkFontFiles = @("UDEVGothic35NF-Regular.ttf", "UDEVGothicNF-Regular.ttf")
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
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes('{"agent": "antigravity", "speed": "extreme", "status": "active"}')
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
    $mmdResult = nu -c '"graph TD\n  A[Client] --> B[Server]" | ^bunx --bun mermaid-ascii' 2>&1 | Out-String
    $mmdOk = $mmdResult -match "Client" -and $mmdResult -match "Server"
    Assert-Test -Name "Mermaid ASCII diagram rendering" -Condition $mmdOk -Details ($mmdResult.Trim())

    # Test 4.7: AI Agent SSOT Rule Synchronization
    $syncCheckProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $rootDir "scripts\sync_agent_rules.ps1"), "-Check" -NoNewWindow -Wait -PassThru
    Assert-Test -Name "AI Agent SSOT Rule Synchronization (Master vs Targets)" -Condition ($syncCheckProc.ExitCode -eq 0) -Details "ExitCode: $($syncCheckProc.ExitCode)"

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
Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Test Summary: $passedCount PASSED, $failedCount FAILED, $warnCount WARNINGS" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "-------------------------------------------------------`n" -ForegroundColor Cyan

if ($failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
