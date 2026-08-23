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

Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Step 3: Runtime & Tool Initialization   " -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# 環境変数の反映（現在のセッションに PATH を再読み込み）
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# --- 1. fnm & Node.js LTS ---
Write-Host "`n>> [1/4] Setting up fnm (Fast Node Manager)..." -ForegroundColor Cyan
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    try {
        Write-Host "   Installing Node.js LTS via fnm..." -ForegroundColor Gray
        fnm install --lts
        fnm default lts-latest
        Write-Host "[OK] Node.js LTS is set as default." -ForegroundColor Green
    } catch {
        Write-Warning "[WARN] Failed to configure fnm: $_"
    }
} else {
    Write-Host "[SKIP] fnm is not in PATH yet. Restarting terminal might be required." -ForegroundColor Yellow
}

# --- 2. uv (Python) ---
Write-Host "`n>> [2/4] Setting up uv (Python Manager)..." -ForegroundColor Cyan
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
Write-Host "`n>> [3/4] Checking Rustup..." -ForegroundColor Cyan
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

Write-Host "`n[DONE] Runtime setup step finished." -ForegroundColor Green
