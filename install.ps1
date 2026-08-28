#Requires -Version 5.1
<#
.SYNOPSIS
    Windows モダン開発環境 (Nushell, Helix, Rust/Go CLI) 統合セットアップスクリプト
.DESCRIPTION
    責務ごとに分割されたスクリプトを順次実行し、開発環境を一括または個別構築します。
.PARAMETER Step
    実行するステップを指定します (1: Winget, 2: Font, 3: Runtimes, 4: Configs, All: すべて)
.PARAMETER UseSymlinks
    設定ファイルをコピーではなくシンボリックリンクで配置します (管理者権限/開発者モード推奨)
.PARAMETER Force
    既にインストール済みのフォントやパッケージがあっても強制的に再取得・再インストールします
.EXAMPLE
    .\install.ps1 -All
    .\install.ps1 -Step 2         # フォントのみ（インストール済みの場合はスキップ）
    .\install.ps1 -Step 2 -Force  # フォントを強制的に再取得して再インストール
#>
[CmdletBinding()]
param(
    [ValidateSet("All", "1", "2", "3", "4")]
    [string]$Step = "All",

    [switch]$All,

    [switch]$UseSymlinks,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptsDir = Join-Path $PSScriptRoot "scripts"

# UTF-8 出力エンコーディングの設定（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

try { Clear-Host } catch {}
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Windows Modern Dev Environment Setup                  " -ForegroundColor Cyan
Write-Host "   (Nushell + Helix + Rust/Go CLI + UDEV Gothic NF)      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-IsAdmin)) {
    Write-Warning "[NOTICE] 管理者権限(Admin)で実行されていません。"
    Write-Warning "一部のパッケージインストールやシンボリックリンク作成には管理者権限を推奨します。"
}

# PowerShell スクリプト実行ポリシーの確認・自動設定（CurrentUser）
try {
    Import-Module Microsoft.PowerShell.Security -ErrorAction SilentlyContinue
    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    if ($null -eq $currentPolicy -or $currentPolicy -eq "Undefined" -or $currentPolicy -eq "Restricted") {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
    }
} catch {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" | Out-Null
    } catch {}
}

$stepsToRun = @()
if ($All -or $Step -eq "All") {
    $stepsToRun = @("1", "2", "3", "4")
} else {
    $stepsToRun = @($Step)
}

function Update-SessionEnvironment {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

foreach ($s in $stepsToRun) {
    Update-SessionEnvironment
    switch ($s) {
        "1" {
            & (Join-Path $scriptsDir "01_winget_packages.ps1")
        }
        "2" {
            $params = @{}
            if ($Force) { $params["Force"] = $true }
            & (Join-Path $scriptsDir "02_install_fonts.ps1") @params
        }
        "3" {
            & (Join-Path $scriptsDir "03_setup_runtimes.ps1")
        }
        "4" {
            $params = @{}
            if ($UseSymlinks) { $params["UseSymlinks"] = $true }
            & (Join-Path $scriptsDir "04_setup_configs.ps1") @params
        }
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   Setup Completed!                                       " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "推奨: ターミナル (Windows Terminal) を再起動してください。" -ForegroundColor Yellow
Write-Host "ヒント: AI Agent の API キーを設定する場合は ``just setup-keys`` を実行してください。" -ForegroundColor DarkGray

