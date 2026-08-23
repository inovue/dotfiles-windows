#Requires -Version 5.1
<#
.SYNOPSIS
    configs/ ディレクトリ内の各種ツール設定ファイル（Dotfiles）をユーザー環境に配置します。
.DESCRIPTION
    既存の設定ファイルが存在する場合は .bak バックアップを作成してから配置します。
#>
[CmdletBinding()]
param(
    [switch]$UseSymlinks
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Step 4: Deploying Configuration Files   " -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

$rootDir = Split-Path -Parent $PSScriptRoot
$configsDir = Join-Path $rootDir "configs"

# Windows Terminal の設定配置先を検出
$wtPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
$wtDest = $wtPaths | Where-Object { Test-Path (Split-Path -Parent $_) } | Select-Object -First 1
if (-not $wtDest) {
    $wtDest = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
}

# 配備マッピング [設定元 相対パス -> 配備先 絶対パス]
$deployTargets = @(
    @{
        Name = "Windows Terminal (settings.json)"
        Src  = Join-Path $configsDir "windows-terminal\settings.json"
        Dest = $wtDest
    },
    @{
        Name = "Helix (config.toml)"
        Src  = Join-Path $configsDir "helix\config.toml"
        Dest = Join-Path $env:APPDATA "helix\config.toml"
    },
    @{
        Name = "Helix (languages.toml)"
        Src  = Join-Path $configsDir "helix\languages.toml"
        Dest = Join-Path $env:APPDATA "helix\languages.toml"
    },
    @{
        Name = "Nushell (config.nu)"
        Src  = Join-Path $configsDir "nushell\config.nu"
        Dest = Join-Path $env:APPDATA "nushell\config.nu"
    },
    @{
        Name = "Nushell (env.nu)"
        Src  = Join-Path $configsDir "nushell\env.nu"
        Dest = Join-Path $env:APPDATA "nushell\env.nu"
    },
    @{
        Name = "Starship (starship.toml)"
        Src  = Join-Path $configsDir "starship\starship.toml"
        Dest = Join-Path (Join-Path $env:USERPROFILE ".config") "starship.toml"
    },
    @{
        Name = "Lazygit (config.yml)"
        Src  = Join-Path $configsDir "lazygit\config.yml"
        Dest = Join-Path $env:LOCALAPPDATA "lazygit\config.yml"
    }
)

foreach ($target in $deployTargets) {
    if (-not (Test-Path $target.Src)) {
        Write-Warning "[SKIP] Source file not found: $($target.Src)"
        continue
    }

    $destDir = Split-Path -Parent $target.Dest
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # 既存ファイルのバックアップ
    if (Test-Path $target.Dest) {
        $backupPath = "$($target.Dest).bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host ">> Backing up existing $($target.Name) -> $backupPath" -ForegroundColor Gray
        Copy-Item -Path $target.Dest -Destination $backupPath -Force
    }

    Write-Host ">> Deploying $($target.Name)..." -ForegroundColor Cyan
    if ($UseSymlinks) {
        try {
            New-Item -ItemType SymbolicLink -Path $target.Dest -Target $target.Src -Force | Out-Null
            Write-Host "[OK] Symlink created: $($target.Dest)" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to create symlink (Developer Mode/Admin required). Copying instead."
            Copy-Item -Path $target.Src -Destination $target.Dest -Force
            Write-Host "[OK] Copied file: $($target.Dest)" -ForegroundColor Green
        }
    } else {
        Copy-Item -Path $target.Src -Destination $target.Dest -Force
        Write-Host "[OK] Copied file: $($target.Dest)" -ForegroundColor Green
    }
}

Write-Host "`n[DONE] Configuration deployment step finished." -ForegroundColor Green
