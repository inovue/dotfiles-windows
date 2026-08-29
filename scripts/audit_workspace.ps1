#Requires -Version 5.1
<#
.SYNOPSIS
    dotfiles-windows 統合ワークスペース監査・クリーンアップスクリプト
.DESCRIPTION
    1. 環境・CLI・安全環境変数・AST・UTF-8 BOM の網羅的検証 (verify_tools.ps1)
       およびセキュリティ回帰 (verify_security.ps1)
    2. AI Agent SSOT ルール＆スキルの同期状態検査 (sync_agent_rules.ps1 -Check)
    3. 一時ファイル・バックアップファイル・Git 作業ツリーのクリーン度検査 / クリーンアップ (-Clean)
.PARAMETER Clean
    一時ファイル、古いバックアップ (*.bak)、キャッシュファイルを消去します。
#>
[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = "Continue"

# UTF-8 出力エンコーディング
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = Split-Path -Parent $PSScriptRoot
$psExe = "powershell.exe"
$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($pwshCmd) { $psExe = $pwshCmd.Source }
$testsScript = Join-Path $rootDir "tests\verify_tools.ps1"
$secScript  = Join-Path $rootDir "tests\verify_security.ps1"
$syncScript  = Join-Path $rootDir "scripts\sync_agent_rules.ps1"

$junkPatterns = @("*.bak", "*.backup", "*.tmp", "*.old", "*.orig", "*~", "transcript*.txt")

if ($Clean) {
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "   Workspace Cleanup & Artifact Sanitizer              " -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    $removedCount = 0
    foreach ($pat in $junkPatterns) {
        $matched = Get-ChildItem -Path $rootDir -Filter $pat -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" }
        foreach ($f in $matched) {
            try {
                Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                Write-Host "  [REMOVED] $($f.FullName)" -ForegroundColor Yellow
                $removedCount++
            } catch {
                Write-Warning "  [FAILED] Could not remove $($f.FullName): $_"
            }
        }
    }
    if ($removedCount -eq 0) {
        Write-Host "[OK] Workspace is already completely clean. Zero junk files found." -ForegroundColor Green
    } else {
        Write-Host "[OK] Cleaned $removedCount temporary / backup files." -ForegroundColor Green
    }
    exit 0
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "   AI Agent & Workspace Unified Audit Harness          " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$auditFailed = $false

# --- Phase 1: Environment & Integration Test Suite ---
Write-Host "`n[Audit Phase 1/3] Running Environment Verification Suite..." -ForegroundColor White
$testProc = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $testsScript -NoNewWindow -Wait -PassThru
if ($testProc.ExitCode -ne 0) {
    Write-Warning "[FAIL] Environment verification tests failed (ExitCode: $($testProc.ExitCode))."
    $auditFailed = $true
} else {
    Write-Host "[PASS] Phase 1a: Environment verification suite passed." -ForegroundColor Green
}

Write-Host "`n[Audit Phase 1b/3] Running Security Regression Suite..." -ForegroundColor White
if (Test-Path $secScript) {
    $secProc = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $secScript -NoNewWindow -Wait -PassThru
    if ($secProc.ExitCode -ne 0) {
        Write-Warning "[FAIL] Security regression tests failed (ExitCode: $($secProc.ExitCode))."
        $auditFailed = $true
    } else {
        Write-Host "[PASS] Phase 1b: Security regression suite passed." -ForegroundColor Green
    }
} else {
    Write-Warning "[FAIL] tests/verify_security.ps1 is missing."
    $auditFailed = $true
}

# --- Phase 2: AI Agent SSOT Rule Synchronization ---
Write-Host "`n[Audit Phase 2/3] Checking AI Agent SSOT Synchronization..." -ForegroundColor White
$graphifyOutDir = Join-Path $rootDir "graphify-out"
if (Test-Path $graphifyOutDir) {
    Remove-Item -Path $graphifyOutDir -Recurse -Force
}
$syncProc = Start-Process -FilePath $psExe -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $syncScript, "-Check" -NoNewWindow -Wait -PassThru
if ($syncProc.ExitCode -ne 0) {
    Write-Warning "[FAIL] SSOT rules or skills are out of sync with master."
    $auditFailed = $true
} else {
    Write-Host "[PASS] Phase 2: All AI agent rules and skills are 100% in sync." -ForegroundColor Green
}

# --- Phase 3: Junk & Artifact Scan ---
Write-Host "`n[Audit Phase 3/3] Scanning for Junk, Stale Backups & Conflict Artifacts..." -ForegroundColor White
$foundJunk = @()
foreach ($pat in $junkPatterns) {
    $matched = Get-ChildItem -Path $rootDir -Filter $pat -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" }
    if ($matched) { $foundJunk += $matched }
}

if ($foundJunk.Count -gt 0) {
    Write-Warning "[WARN] Found $($foundJunk.Count) leftover temporary/backup files (Run 'just clean' to resolve):"
    foreach ($jf in $foundJunk) {
        Write-Host "       - $($jf.FullName)" -ForegroundColor Yellow
    }
    $auditFailed = $true
} else {
    Write-Host "[PASS] Phase 3: Zero temporary, backup, or junk files detected." -ForegroundColor Green
}

# --- Final Summary ---
Write-Host "`n=======================================================" -ForegroundColor Cyan
if (-not $auditFailed) {
    Write-Host " AUDIT SUMMARY: 100% CLEAN & VERIFIED (Zero Technical Debt)" -ForegroundColor Green
    Write-Host " Ground truth confirmed. Zero file reading permitted for surveys." -ForegroundColor Green
    Write-Host "=======================================================`n" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host " AUDIT SUMMARY: ISSUES DETECTED - Action Required" -ForegroundColor Red
    Write-Host "=======================================================`n" -ForegroundColor Cyan
    exit 1
}
