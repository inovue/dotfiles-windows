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
.EXAMPLE
    .\install.ps1 -All
    .\install.ps1 -Step 2  # フォントのみインストール
#>
[CmdletBinding()]
param(
    [ValidateSet("All", "1", "2", "3", "4")]
    [string]$Step = "All",

    [switch]$UseSymlinks
)

$ErrorActionPreference = "Stop"
$scriptsDir = Join-Path $PSScriptRoot "scripts"

function Test-IsAdmin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Windows Modern Dev Environment Setup                  " -ForegroundColor Cyan
Write-Host "   (Nushell + Helix + Rust/Go CLI + UDEV Gothic NF)      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-IsAdmin)) {
    Write-Warning "[NOTICE] 管理者権限(Admin)で実行されていません。"
    Write-Warning "一部のパッケージインストールやシンボリックリンク作成には管理者権限を推奨します。"
}

$stepsToRun = @()
if ($Step -eq "All") {
    $stepsToRun = @("1", "2", "3", "4")
} else {
    $stepsToRun = @($Step)
}

foreach ($s in $stepsToRun) {
    switch ($s) {
        "1" {
            & (Join-Path $scriptsDir "01_winget_packages.ps1")
        }
        "2" {
            & (Join-Path $scriptsDir "02_install_fonts.ps1")
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
