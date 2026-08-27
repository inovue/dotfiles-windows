#Requires -Version 5.1
<#
.SYNOPSIS
    Cursor × Windows ハーネス基盤をセットアップ時に固定し、エージェントが前提として使える状態にする。
.DESCRIPTION
    - Windows ユーザー環境変数 (UTF-8, pager, telemetry, DOTFILES_HARNESS)
    - ~/.local/bin を User PATH 先頭に追加
    - configs/cursor/harness-settings.json を Cursor User settings.json に外科マージ
    - ~/.cursor/harness-baseline.json マニフェストを書き込み
    sync_agent_rules.ps1 の前後どちらから呼んでも冪等。
.PARAMETER Check
    適用せず、環境変数・PATH・Cursor settings・マニフェストの一致のみ検査 (exit 1 = drift)。
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$mergePy = Join-Path $PSScriptRoot "merge_cursor_agent_shell.py"
$baselineVersion = "cursor-windows-v1"

$UserEnv = [ordered]@{
    DOTFILES_HARNESS            = $baselineVersion
    PYTHONUTF8                  = "1"
    PYTHONDONTWRITEBYTECODE     = "1"
    POWERSHELL_TELEMETRY_OPTOUT = "1"
    DOTNET_CLI_TELEMETRY_OPTOUT = "1"
    GIT_PAGER                   = "cat"
    PAGER                       = "cat"
}

function Test-UserEnvInSync {
    foreach ($entry in $UserEnv.GetEnumerator()) {
        $got = [Environment]::GetEnvironmentVariable($entry.Key, "User")
        if ($got -ne $entry.Value) { return $false }
    }
    return $true
}

function Set-UserEnvHarness {
    foreach ($entry in $UserEnv.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "User")
    }
}

function Test-LocalBinOnUserPath {
    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { return $false }
    $first = ($userPath -split ';' | Where-Object { $_ } | Select-Object -First 1)
    try {
        return ([System.IO.Path]::GetFullPath($first) -eq [System.IO.Path]::GetFullPath($localBin))
    } catch {
        return $userPath -like "*$localBin*"
    }
}

function Ensure-LocalBinOnUserPath {
    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    if (-not (Test-Path $localBin)) {
        New-Item -Path $localBin -ItemType Directory -Force | Out-Null
    }
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -like "*$localBin*") {
        if (Test-LocalBinOnUserPath) { return }
        $parts = @($localBin) + ($userPath -split ';' | Where-Object { $_ -and $_ -ne $localBin })
        [Environment]::SetEnvironmentVariable("Path", ($parts -join ';'), "User")
        return
    }
    if ($userPath) {
        [Environment]::SetEnvironmentVariable("Path", "$localBin;$userPath", "User")
    } else {
        [Environment]::SetEnvironmentVariable("Path", $localBin, "User")
    }
}

function Get-BaselineManifestPath {
    return Join-Path (Join-Path $env:USERPROFILE ".cursor") "harness-baseline.json"
}

function Test-BaselineManifest {
    $path = Get-BaselineManifestPath
    if (-not (Test-Path $path)) { return $false }
    try {
        $data = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return ($data.version -eq $baselineVersion) -and ($data.harness -eq "cursor-windows")
    } catch {
        return $false
    }
}

function Write-BaselineManifest {
    $path = Get-BaselineManifestPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $obj = [ordered]@{
        version    = $baselineVersion
        harness    = "cursor-windows"
        repo       = $rootDir
        applied_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $json = ($obj | ConvertTo-Json -Depth 3) + "`n"
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-CursorSettingsMerge {
    param([switch]$CheckOnly)
    if (-not (Test-Path $mergePy)) {
        throw "merge script missing: $mergePy"
    }
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    $py = if ($pyCmd) { $pyCmd.Source } else { "python" }
    $args = @($mergePy)
    if ($CheckOnly) { $args += "--check" }
    & $py @args 2>&1 | Out-Null
    return [int]$LASTEXITCODE
}

Write-Host ">> Cursor harness baseline (env + PATH + settings)..." -ForegroundColor Cyan

$drift = @()
if (-not (Test-UserEnvInSync)) { $drift += "user-env" }
if (-not (Test-LocalBinOnUserPath)) { $drift += "user-path" }
$mergeExit = Invoke-CursorSettingsMerge -CheckOnly
if ($mergeExit -ne 0) { $drift += "cursor-settings" }
if (-not (Test-BaselineManifest)) { $drift += "baseline-manifest" }

if ($Check) {
    if ($drift.Count -eq 0) {
        Write-Host "  [OK] Harness baseline in sync." -ForegroundColor Green
        exit 0
    }
    Write-Host "  [DRIFT] $($drift -join ', ')" -ForegroundColor Yellow
    exit 1
}

if ($drift.Count -eq 0) {
    Write-Host "  [OK] Harness baseline already applied." -ForegroundColor DarkGray
    exit 0
}

Set-UserEnvHarness
Write-Host "  [SYNCED] User environment variables." -ForegroundColor Green

Ensure-LocalBinOnUserPath
Write-Host "  [SYNCED] User PATH (~/.local/bin)." -ForegroundColor Green

$mergeExit = Invoke-CursorSettingsMerge
if ($mergeExit -ne 0) {
    Write-Warning "Cursor settings merge failed (exit $mergeExit). Is Cursor installed?"
} else {
    Write-Host "  [SYNCED] Cursor User settings.json (harness-settings)." -ForegroundColor Green
}

Write-BaselineManifest
Write-Host "  [SYNCED] harness-baseline.json manifest." -ForegroundColor Green

Write-Host "[DONE] Cursor harness baseline fixed for this machine." -ForegroundColor Green
