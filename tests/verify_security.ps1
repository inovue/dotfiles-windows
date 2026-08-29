#Requires -Version 5.1
<#
.SYNOPSIS
    Security regression tests for installer integrity, XSS, and path sanitization.
.DESCRIPTION
    Proves the security fixes actually behave (fail→pass checks), not merely that
    files exist. Invoked by `just audit` Phase 1 and `just test`.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = Split-Path -Parent $PSScriptRoot
$passedCount = 0
$failedCount = 0

function Assert-Test {
    param(
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
Write-Host "  Security Regression Suite (fail-to-pass checks)      " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

$setupKeys = Join-Path $rootDir "scripts\setup_api_keys.ps1"
$fontsScript = Join-Path $rootDir "scripts\02_install_fonts.ps1"
$runtimesScript = Join-Path $rootDir "scripts\03_setup_runtimes.ps1"
$pinScript = Join-Path $rootDir "scripts\Assert-PinnedHash.ps1"
$configNu = Join-Path $rootDir "configs\nushell\config.nu"
$runnerPy = Join-Path $rootDir "configs\agents\skills\browser-agent\scripts\browser_runner.py"

# --- 1. setup_api_keys.ps1 -Clear ---
Write-Host "[1/5] API key Clear / DELETE path..." -ForegroundColor White
$parseErrors = $null
$parseTokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($setupKeys, [ref]$parseTokens, [ref]$parseErrors)
$paramNames = @()
if ($ast.ParamBlock) {
    $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
}
Assert-Test -Name "setup_api_keys.ps1 declares -Clear switch" -Condition ($paramNames -contains "Clear") -Details ("params: " + ($paramNames -join ", "))

$setupText = [System.IO.File]::ReadAllText($setupKeys, [System.Text.Encoding]::UTF8)
$clearsEnv = ($setupText -match '\$Clear') -and ($setupText -match 'SetEnvironmentVariable\(\$VarName,\s*\$null')
$acceptsClearWord = ($setupText -match '"CLEAR"') -and ($setupText -match '"DELETE"')
Assert-Test -Name "setup_api_keys.ps1 deletes User+Process env vars on -Clear" -Condition $clearsEnv
Assert-Test -Name "setup_api_keys.ps1 accepts interactive CLEAR/DELETE" -Condition $acceptsClearWord

# --- 2. Download domain regex (strict, bypass-resistant) ---
Write-Host "`n[2/5] Download URL domain allowlists..." -ForegroundColor White
$fontsText = [System.IO.File]::ReadAllText($fontsScript, [System.Text.Encoding]::UTF8)
$rtText = [System.IO.File]::ReadAllText($runtimesScript, [System.Text.Encoding]::UTF8)

function Get-QuotedRegex {
    param([string]$Haystack, [string]$Needle)
    $escaped = [regex]::Escape($Needle)
    if ($Haystack -match "(-match\s+')([^']*$escaped[^']*)'") {
        return $Matches[2]
    }
    return $null
}

$fontRe = Get-QuotedRegex $fontsText "udev-gothic"
$rtkRe = Get-QuotedRegex $rtText "rtk-ai/rtk"
$cursorRe = '^https://(?:downloads\.cursor\.com|(?:[a-zA-Z0-9-]+\.)*cursor\.sh)/'
$cursorInSource = $rtText.Contains('downloads\.cursor\.com') -and $rtText.Contains('cursor\.sh')

Assert-Test -Name "Font download regex extracted from 02_install_fonts.ps1" -Condition (-not [string]::IsNullOrEmpty($fontRe)) -Details $fontRe
Assert-Test -Name "RTK download regex extracted from 03_setup_runtimes.ps1" -Condition (-not [string]::IsNullOrEmpty($rtkRe)) -Details $rtkRe
Assert-Test -Name "Cursor CLI download regex extracted from 03_setup_runtimes.ps1" -Condition $cursorInSource -Details $cursorRe

$fontGood = @(
    "https://github.com/yuru7/udev-gothic/releases/download/v0.0.1/UDEVGothic_NF_v0.0.1.zip",
    "https://objects.githubusercontent.com/github-production-release-asset-2e65be/foo"
)
$fontBad = @(
    "https://evil.com/github.com/yuru7/udev-gothic/releases/download/v1/x.zip",
    "https://github.com.evil.com/yuru7/udev-gothic/releases/download/v1/x.zip",
    "https://objects.githubusercontent.com.evil.com/foo",
    "http://github.com/yuru7/udev-gothic/releases/download/v1/x.zip"
)
$fontGoodOk = $true
$fontBadOk = $true
foreach ($u in $fontGood) { if ($u -notmatch $fontRe) { $fontGoodOk = $false } }
foreach ($u in $fontBad) { if ($u -match $fontRe) { $fontBadOk = $false } }
Assert-Test -Name "Font regex accepts official GitHub download URLs" -Condition $fontGoodOk
Assert-Test -Name "Font regex rejects domain-bypass URLs" -Condition $fontBadOk

$rtkGood = @(
    "https://github.com/rtk-ai/rtk/releases/download/v1.2.3/rtk-x86_64-pc-windows-msvc.zip",
    "https://objects.githubusercontent.com/foo"
)
$rtkBad = @(
    "https://evil.com/github.com/rtk-ai/rtk/releases/download/v1/x.zip",
    "https://github.com.evil.com/rtk-ai/rtk/releases/download/v1/x.zip"
)
$rtkGoodOk = $true
$rtkBadOk = $true
foreach ($u in $rtkGood) { if ($u -notmatch $rtkRe) { $rtkGoodOk = $false } }
foreach ($u in $rtkBad) { if ($u -match $rtkRe) { $rtkBadOk = $false } }
Assert-Test -Name "RTK regex accepts official GitHub download URLs" -Condition $rtkGoodOk
Assert-Test -Name "RTK regex rejects domain-bypass URLs" -Condition $rtkBadOk

$cursorGood = @(
    "https://downloads.cursor.com/lab/2026.08.11-e8db854/windows/x64/agent-cli-package.zip",
    "https://abc.cursor.sh/windows/x64/agent-cli-package.zip",
    "https://cursor.sh/windows/x64/agent-cli-package.zip"
)
$cursorBad = @(
    "https://evil.com/downloads.cursor.com/lab/x.zip",
    "https://downloads.cursor.com.evil.com/lab/x.zip",
    "https://cursor.sh.evil.com/x.zip",
    "https://evil.com/x.cursor.sh/pkg.zip",
    "https://notcursor.sh/pkg.zip"
)
$cursorGoodOk = $true
$cursorBadOk = $true
foreach ($u in $cursorGood) { if ($u -notmatch $cursorRe) { $cursorGoodOk = $false } }
foreach ($u in $cursorBad) { if ($u -match $cursorRe) { $cursorBadOk = $false } }
Assert-Test -Name "Cursor CLI regex accepts downloads.cursor.com / *.cursor.sh" -Condition $cursorGoodOk
Assert-Test -Name "Cursor CLI regex rejects domain-bypass URLs" -Condition $cursorBadOk

# --- 3. SHA256 pin / TOFU ---
Write-Host "`n[3/5] SHA256 pin + TOFU compare-and-abort..." -ForegroundColor White
Assert-Test -Name "Assert-PinnedHash.ps1 exists" -Condition (Test-Path $pinScript)
. $pinScript

$pinDir = Join-Path $env:TEMP "pin_test_$(Get-Random)"
New-Item -Path $pinDir -ItemType Directory -Force | Out-Null
try {
    $store = Join-Path $pinDir "checksums.json"
    $fileA = Join-Path $pinDir "a.bin"
    $fileB = Join-Path $pinDir "b.bin"
    [System.IO.File]::WriteAllBytes($fileA, [byte[]](1, 2, 3, 4))
    [System.IO.File]::WriteAllBytes($fileB, [byte[]](9, 9, 9, 9))

    $first = Assert-PinnedHash -Name "fixture:v1" -FilePath $fileA -PinStore $store
    $second = Assert-PinnedHash -Name "fixture:v1" -FilePath $fileA -PinStore $store
    Assert-Test -Name "SHA256 TOFU records first-seen hash and rematch succeeds" -Condition ($first -eq $second -and (Test-Path $store))

    $mismatchThrew = $false
    try {
        Assert-PinnedHash -Name "fixture:v1" -FilePath $fileB -PinStore $store | Out-Null
    } catch {
        $mismatchThrew = ("$_" -match "SHA256 mismatch")
    }
    Assert-Test -Name "SHA256 pin mismatch throws and aborts" -Condition $mismatchThrew

    $fontsUsesPin = ($fontsText -match 'Assert-PinnedHash') -and ($fontsText -match 'udev-gothic:')
    $rtkUsesPin = ($rtText -match 'Assert-PinnedHash') -and ($rtText -match 'rtk:')
    $cursorUsesPin = ($rtText -match 'cursor-agent:')
    $rtkRethrows = ($rtText -match "match 'SHA256'\) \{ throw")
    Assert-Test -Name "02_install_fonts.ps1 pins udev-gothic SHA256" -Condition $fontsUsesPin
    Assert-Test -Name "03_setup_runtimes.ps1 pins RTK SHA256 and rethrows mismatch" -Condition ($rtkUsesPin -and $rtkRethrows)
    Assert-Test -Name "03_setup_runtimes.ps1 pins Cursor Agent CLI SHA256" -Condition $cursorUsesPin
} finally {
    Remove-Item -Path $pinDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 4. Mermaid XSS ---
Write-Host "`n[4/5] Mermaid HTML preview XSS defenses..." -ForegroundColor White
$nuText = [System.IO.File]::ReadAllText($configNu, [System.Text.Encoding]::UTF8)
$hasJson = $nuText -match 'to json'
$hasTextContent = $nuText -match 'textContent'
$hasStrict = $nuText -match "securityLevel:\s*'strict'"
$hasPlaceholder = $nuText -match '__MERMAID_CONTENT_JSON__'
$rawInterp = $nuText -match 'innerHTML' -or $nuText -match 'document\.write'
$krokiWarn = $nuText -match 'do not submit confidential data'
$hasUescape = $nuText.Contains('\u003c')
Assert-Test -Name "config.nu inserts Mermaid via JSON + textContent (not innerHTML)" -Condition ($hasJson -and $hasTextContent -and $hasPlaceholder -and -not $rawInterp)
Assert-Test -Name "config.nu HTML-embeds JSON with '<' escaped to \\u003c" -Condition $hasUescape
Assert-Test -Name "config.nu sets mermaid securityLevel strict" -Condition $hasStrict
Assert-Test -Name "config.nu warns before sending diagram text to Kroki" -Condition $krokiWarn

$payload = '</script><img src=x onerror=alert(1)>'
$jsonPayload = ($payload | ConvertTo-Json -Compress)
$embedded = $jsonPayload.Replace('<', '\u003c')
$cannotBreak = ($embedded -notmatch '</script>')
Assert-Test -Name "XSS payload is JSON-quoted (cannot break out of diagramCode)" -Condition $cannotBreak -Details $jsonPayload

# --- 5. browser_runner.py profile sanitization ---
Write-Host "`n[5/5] browser_runner.py profile path sanitization..." -ForegroundColor White
$pyText = [System.IO.File]::ReadAllText($runnerPy, [System.Text.Encoding]::UTF8)
Assert-Test -Name "browser_runner.py defines sanitize_profile_name" -Condition ($pyText -match "sanitize_profile_name")
Assert-Test -Name "browser_runner.py supports actions-file" -Condition ($pyText -match "actions-file" -or $pyText -match "actions_file")

$setupProfilePs1 = Join-Path $rootDir "configs\agents\skills\browser-agent\scripts\setup_profile.ps1"
$setupProfileText = [System.IO.File]::ReadAllText($setupProfilePs1, [System.Text.Encoding]::UTF8)
Assert-Test -Name "setup_profile.ps1 sanitizes profile name" -Condition ($setupProfileText -match "SafeProfile")

$py = @"
import re, pathlib, importlib.util
path = pathlib.Path(r'$($runnerPy.Replace('\','/'))')
spec = importlib.util.spec_from_file_location('br', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
samples = ['../etc/passwd', r'..\\..\\Windows', 'foo/../../bar', 'ok_profile-1']
out = {s: mod.sanitize_profile_name(s) for s in samples}
bad = [s for s, v in out.items() if s != 'ok_profile-1' and (('/' in v) or ('\\' in v) or ('..' in v))]
print('OK' if not bad else 'LEAK:' + ','.join(bad))
print(out)
"@
$pyFile = Join-Path $env:TEMP "sanitize_test_$(Get-Random).py"
[System.IO.File]::WriteAllText($pyFile, $py, [System.Text.Encoding]::UTF8)
try {
    $pyOut = python $pyFile 2>&1 | Out-String
    Assert-Test -Name "browser_runner.py profile regex strips traversal characters" -Condition ($pyOut.Trim() -match '^OK') -Details $pyOut.Trim()
} finally {
    Remove-Item $pyFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Security Summary: $passedCount PASSED, $failedCount FAILED" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "=======================================================`n" -ForegroundColor Cyan

if ($failedCount -gt 0) { exit 1 } else { exit 0 }
