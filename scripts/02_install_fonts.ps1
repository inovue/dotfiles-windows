#Requires -Version 5.1
<#
.SYNOPSIS
    yuru7/HackGen リポジトリから最新の HackGen_NF (Nerd Fonts 対応日本語フォント) を自動取得・インストールします。
.DESCRIPTION
    GitHub API を使用して最新リリース ZIP をダウンロード・解凍し、
    Windows のフォント管理システムに自動登録します。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Step 2: Japanese Font (HackGen_NF) Setup" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

$repoOwner = "yuru7"
$repoName = "HackGen"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"

try {
    Write-Host "`n>> Fetching latest release info from GitHub ($repoOwner/$repoName)..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell-SetupScript" }
    
    # HackGen_NF_v*.zip を対象にする
    $asset = $release.assets | Where-Object { $_.name -match "^HackGen_NF_v.*\.zip$" } | Select-Object -First 1

    if (-not $asset) {
        throw "HackGen_NF の ZIP アセットが見つかりませんでした。"
    }

    $downloadUrl = $asset.browser_download_url
    $zipFileName = $asset.name
    $tempZipPath = Join-Path $env:TEMP $zipFileName
    $tempExtractDir = Join-Path $env:TEMP "HackGen_NF_Extracted"

    Write-Host ">> Downloading $($asset.name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipPath

    if (Test-Path $tempExtractDir) {
        Remove-Item $tempExtractDir -Recurse -Force
    }

    Write-Host ">> Extracting files..." -ForegroundColor Cyan
    Expand-Archive -Path $tempZipPath -DestinationPath $tempExtractDir -Force

    # TTF ファイルの収集
    $fontFiles = Get-ChildItem -Path $tempExtractDir -Recurse -Include "*.ttf"

    if ($fontFiles.Count -eq 0) {
        throw "展開されたディレクトリ内に .ttf フォントファイルが見つかりませんでした。"
    }

    Write-Host ">> Installing $($fontFiles.Count) font files to Windows..." -ForegroundColor Cyan

    # Shell.Application を使って Fonts フォルダ (0x14) にコピー登録
    $shellApp = New-Object -ComObject Shell.Application
    $fontsFolder = $shellApp.NameSpace(0x14)

    foreach ($file in $fontFiles) {
        Write-Host "   Installing: $($file.Name)" -ForegroundColor Gray
        $fontsFolder.CopyHere($file.FullName, 16) # 16 = "Yes to All" (上書き確認ダイアログのスキップ)
    }

    # 一時ファイルの削除
    Remove-Item $tempZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n[OK] HackGen_NF (HackGen Console NF) installed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "[FAIL] Failed to install HackGen_NF: $_"
    exit 1
}
