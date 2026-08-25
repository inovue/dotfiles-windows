#Requires -Version 5.1
<#
.SYNOPSIS
    yuru7/udev-gothic リポジトリから最新の UDEV Gothic NF (UDEV Gothic 35NF / Nerd Fonts 対応) を自動取得・インストールします。
.DESCRIPTION
    GitHub API を使用して最新リリース ZIP (UDEVGothic_NF_v*.zip) をダウンロード・解凍し、
    Windows のフォント管理システムに自動登録します。
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# UTF-8 出力エンコーディングの設定（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Step 2: Japanese Font (UDEV Gothic NF)  " -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

function Test-FontInstalled {
    $checkFontFiles = @("UDEVGothic35NF-Regular.ttf", "UDEVGothicNF-Regular.ttf")
    $checkRegKeys   = @("UDEVGothic35NF-Regular (TrueType)", "UDEVGothicNF-Regular (TrueType)")

    # 1. ファイルの存在確認 (SystemRoot または LOCALAPPDATA)
    $hasFile = $false
    foreach ($fontFile in $checkFontFiles) {
        if ((Test-Path (Join-Path "$env:SystemRoot\Fonts" $fontFile)) -or `
            (Test-Path (Join-Path "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" $fontFile))) {
            $hasFile = $true
            break
        }
    }

    if (-not $hasFile) {
        return $false
    }

    # 2. レジストリ登録の確認 (HKLM または HKCU)
    $hklmProps = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue
    $hkcuProps = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue

    foreach ($regKey in $checkRegKeys) {
        if (($hklmProps -and $hklmProps.$regKey) -or ($hkcuProps -and $hkcuProps.$regKey)) {
            return $true
        }
    }

    return $false
}

if (-not $Force -and (Test-FontInstalled)) {
    Write-Host "`n[SKIP] UDEV Gothic NF (UDEV Gothic 35NF) is already installed." -ForegroundColor Yellow
    Write-Host "       (Pass -Force to re-download and reinstall)" -ForegroundColor Gray
    return
}

$repoOwner = "yuru7"
$repoName = "udev-gothic"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"

try {
    Write-Host "`n>> Fetching latest release info from GitHub ($repoOwner/$repoName)..." -ForegroundColor Cyan
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell-SetupScript" }
    
    # UDEVGothic_NF_v*.zip を対象にする
    $asset = $release.assets | Where-Object { $_.name -match "^UDEVGothic_NF_v.*\.zip$" } | Select-Object -First 1

    if (-not $asset) {
        throw "UDEVGothic_NF の ZIP アセットが見つかりませんでした。"
    }

    $downloadUrl = $asset.browser_download_url
    $zipFileName = $asset.name
    $tempZipPath = Join-Path $env:TEMP $zipFileName
    $tempExtractDir = Join-Path $env:TEMP "UDEVGothic_NF_Extracted"

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

    function Test-IsAdmin {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    $isAdmin = Test-IsAdmin
    if ($isAdmin) {
        $targetFontDir = "$env:SystemRoot\Fonts"
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    } else {
        $targetFontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
        $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    }

    if (-not (Test-Path $targetFontDir)) {
        New-Item -Path $targetFontDir -ItemType Directory -Force | Out-Null
    }

    if (-not ([System.Management.Automation.PSTypeName]'FontNativeHelper').Type) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class FontNativeHelper {
            [DllImport("gdi32.dll", EntryPoint="AddFontResourceW", SetLastError=true)]
            public static extern int AddFontResource([MarshalAs(UnmanagedType.LPWStr)] string lpFileName);
            [DllImport("user32.dll")]
            public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
        }
"@
    }

    foreach ($file in $fontFiles) {
        $destFile = Join-Path $targetFontDir $file.Name
        Write-Host "   Installing: $($file.Name)" -ForegroundColor Gray
        try {
            Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction Stop
        } catch [System.IO.IOException] {
            Write-Host "   [IN-USE] $($file.Name) is in use by a running application (skipped copy)." -ForegroundColor Yellow
        }

        $fontName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $regValue = if ($isAdmin) { $file.Name } else { $destFile }
        Set-ItemProperty -Path $regPath -Name "$fontName (TrueType)" -Value $regValue -Force | Out-Null

        [FontNativeHelper]::AddFontResource($destFile) | Out-Null
    }

    [FontNativeHelper]::SendMessage([IntPtr]0xffff, 0x001D, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null

    # 一時ファイルの削除
    Remove-Item $tempZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n[OK] UDEV Gothic NF (UDEV Gothic 35NF) installed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "[FAIL] Failed to install UDEV Gothic NF: $_"
    exit 1
}
