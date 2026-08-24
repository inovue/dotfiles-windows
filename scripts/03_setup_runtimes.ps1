#Requires -Version 5.1
<#
.SYNOPSIS
    インストールされたランタイム・CLIツールの初期化・セットアップを行います。
.DESCRIPTION
    - fnm による Node.js (LTS) の自動インストール
    - uv による Python ランタイムの自動導入
    - rustup の初期設定
    - tealdeer (tldr) のキャッシュ更新
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# UTF-8 出力エンコーディングの設定（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Step 3: Runtime & Tool Initialization   " -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# 環境変数の反映（現在のセッションに PATH を再読み込み）
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# --- 1. fnm & Node.js LTS ---
Write-Host "`n>> [1/5] Setting up fnm (Fast Node Manager)..." -ForegroundColor Cyan
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    try {
        Write-Host "   Installing Node.js LTS via fnm..." -ForegroundColor Gray
        fnm install --lts
        fnm default lts-latest
        # 現在のセッションにも fnm の Node パスを反映
        fnm env --use-on-cd | Out-String | Invoke-Expression
        Write-Host "[OK] Node.js LTS is set as default." -ForegroundColor Green
    } catch {
        Write-Warning "[WARN] Failed to configure fnm: $_"
    }
} else {
    Write-Host "[SKIP] fnm is not in PATH yet. Restarting terminal might be required." -ForegroundColor Yellow
}

# --- 2. uv (Python) ---
Write-Host "`n>> [2/5] Setting up uv (Python Manager)..." -ForegroundColor Cyan
if (Get-Command uv -ErrorAction SilentlyContinue) {
    try {
        Write-Host "   Installing latest stable Python via uv..." -ForegroundColor Gray
        uv python install 3.12 3.13
        Write-Host "[OK] Python 3.12/3.13 installed via uv." -ForegroundColor Green
    } catch {
        Write-Warning "[WARN] Failed to configure uv: $_"
    }
} else {
    Write-Host "[SKIP] uv is not in PATH yet." -ForegroundColor Yellow
}

# --- 3. Rustup ---
Write-Host "`n>> [3/5] Checking Rustup..." -ForegroundColor Cyan
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    try {
        Write-Host "   Setting default Rust toolchain to stable..." -ForegroundColor Gray
        rustup default stable
        Write-Host "[OK] Rust stable toolchain configured." -ForegroundColor Green
    } catch {
        Write-Warning "[WARN] Failed to configure rustup: $_"
    }
} else {
    Write-Host "[SKIP] rustup is not in PATH yet." -ForegroundColor Yellow
}

# --- 4. tealdeer (tldr) ---
Write-Host "`n>> [4/5] Updating tealdeer (tldr) cache..." -ForegroundColor Cyan
if (Get-Command tldr -ErrorAction SilentlyContinue) {
    try {
        tldr --update
        Write-Host "[OK] tealdeer cache updated." -ForegroundColor Green
    } catch {
        Write-Warning "[WARN] Failed to update tldr cache: $_"
    }
} else {
    Write-Host "[SKIP] tldr is not in PATH yet." -ForegroundColor Yellow
}

# --- 5. Hunk (TUI Diff Reviewer for AI Agents) ---
Write-Host "`n>> [5/5] Installing Hunk (hunkdiff)..." -ForegroundColor Cyan
try {
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        # PNPM_HOME と bin ディレクトリの自動設定（未設定時のエラー防止）
        $pnpmHome = [System.Environment]::GetEnvironmentVariable("PNPM_HOME", "User")
        if (-not $pnpmHome) {
            $pnpmHome = Join-Path $env:LOCALAPPDATA "pnpm"
            [System.Environment]::SetEnvironmentVariable("PNPM_HOME", $pnpmHome, "User")
        }
        $env:PNPM_HOME = $pnpmHome
        $pnpmBin = Join-Path $pnpmHome "bin"
        
        $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $newPaths = @()
        if ($currentUserPath -notlike "*$pnpmBin*") { $newPaths += $pnpmBin }
        if ($currentUserPath -notlike "*$pnpmHome*") { $newPaths += $pnpmHome }
        if ($newPaths.Count -gt 0) {
            [System.Environment]::SetEnvironmentVariable("Path", ($newPaths -join ";") + ";" + $currentUserPath, "User")
        }

        if ($env:Path -notlike "*$pnpmBin*") { $env:Path = "$pnpmBin;$env:Path" }
        if ($env:Path -notlike "*$pnpmHome*") { $env:Path = "$pnpmHome;$env:Path" }

        pnpm setup 2>&1 | Out-Null

        Write-Host "   Installing hunkdiff via pnpm..." -ForegroundColor Gray
        pnpm add -g hunkdiff
        Write-Host "[OK] hunkdiff installed via pnpm." -ForegroundColor Green
    } elseif (Get-Command bun -ErrorAction SilentlyContinue) {
        Write-Host "   Installing hunkdiff via bun..." -ForegroundColor Gray
        bun add -g hunkdiff
        Write-Host "[OK] hunkdiff installed via bun." -ForegroundColor Green
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "   Installing hunkdiff via npm..." -ForegroundColor Gray
        npm install -g hunkdiff
        Write-Host "[OK] hunkdiff installed via npm." -ForegroundColor Green
    } else {
        Write-Host "[SKIP] Node/Bun package manager not in PATH yet. Run 'pnpm add -g hunkdiff' after restarting terminal." -ForegroundColor Yellow
    }
} catch {
    Write-Warning "[WARN] Failed to install hunkdiff: $_"
}

# --- 6. AI Agent Environment Variables & Non-Interactive Safety ---
Write-Host "`n>> [6/7] Configuring AI Agent Safety & Performance Environment Variables..." -ForegroundColor Cyan
$envVarsToSet = @{
    "PAGER"                     = "cat"
    "BAT_PAGER"                 = ""
    "BAT_STYLE"                 = "plain"
    "GIT_PAGER"                 = "cat"
    "DELTA_PAGER"               = "cat"
    "PYTHONUTF8"                = "1"
    "POWERSHELL_TELEMETRY_OPTOUT" = "1"
    "DOTNET_CLI_TELEMETRY_OPTOUT" = "1"
}
foreach ($key in $envVarsToSet.Keys) {
    $val = $envVarsToSet[$key]
    [System.Environment]::SetEnvironmentVariable($key, $val, "User")
    Set-Item -Path "env:$key" -Value $val
}
Write-Host "[OK] Agent non-interactive pager bypass & UTF-8 variables set in User scope." -ForegroundColor Green

# --- 7. ~/.local/bin & Coreutils Shim Directory ---
Write-Host "`n>> [7/7] Setting up ~/.local/bin shim directory in PATH..." -ForegroundColor Cyan
$localBinDir = Join-Path $env:USERPROFILE ".local\bin"
if (-not (Test-Path $localBinDir)) {
    New-Item -Path $localBinDir -ItemType Directory -Force | Out-Null
}

$currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($currentUserPath -notlike "*$localBinDir*") {
    $updatedUserPath = "$localBinDir;" + $currentUserPath
    [System.Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")
    Write-Host "[OK] Added $localBinDir to User PATH." -ForegroundColor Green
} else {
    Write-Host "[OK] $localBinDir is already in User PATH." -ForegroundColor Green
}
if ($env:Path -notlike "*$localBinDir*") {
    $env:Path = "$localBinDir;$env:Path"
}

# Link Coreutils, Cargo, and WinGet modern CLI executables into ~/.local/bin
$shimSourceDirs = @(
    "C:\Program Files\coreutils\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
    "$env:USERPROFILE\.cargo\bin"
)

# Search WinGet Packages for ast-grep, sd, and other tools if not already linked
$wingetPkgDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
if (Test-Path $wingetPkgDir) {
    $foundExes = Get-ChildItem -Path $wingetPkgDir -Recurse -Include "ast-grep.exe", "sg.exe", "sd.exe", "difft.exe", "xh.exe", "procs.exe", "hexyl.exe" -ErrorAction SilentlyContinue
    foreach ($f in $foundExes) {
        $shimPath = Join-Path $localBinDir $f.Name
        if (-not (Test-Path $shimPath)) {
            Copy-Item -Path $f.FullName -Destination $shimPath -Force -ErrorAction SilentlyContinue
        }
    }
}

foreach ($srcDir in $shimSourceDirs) {
    if (Test-Path $srcDir) {
        $exes = Get-ChildItem -Path $srcDir -Filter "*.exe" -File
        foreach ($exe in $exes) {
            $shimPath = Join-Path $localBinDir $exe.Name
            if (-not (Test-Path $shimPath)) {
                try {
                    New-Item -ItemType HardLink -Path $shimPath -Target $exe.FullName -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {
                    Copy-Item -Path $exe.FullName -Destination $shimPath -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
    }
}
Write-Host "[OK] Modern CLI and Coreutils shims verified in $localBinDir." -ForegroundColor Green

Write-Host "`n[DONE] Runtime setup step finished." -ForegroundColor Green
