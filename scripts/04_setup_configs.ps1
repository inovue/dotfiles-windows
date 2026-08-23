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

# --- Windows Terminal 設定のデプロイ＆スマートマージ関数 ---
function Deploy-WindowsTerminalConfig {
    param (
        [string]$SrcPath,
        [string]$DestPath
    )

    if (-not (Test-Path $SrcPath)) {
        Write-Warning "[SKIP] Windows Terminal テンプレートが見つかりません: $SrcPath"
        return
    }

    Write-Host "`n>> Deploying Windows Terminal Configuration..." -ForegroundColor Cyan

    $destDir = Split-Path -Parent $DestPath
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    # Nushell fragment の配置/検証 (Windows Terminal が nu.exe を常に認識・実行できるようにする)
    $nuExePath = ""
    $nuCmd = Get-Command nu -ErrorAction SilentlyContinue
    if ($nuCmd) {
        $nuExePath = $nuCmd.Source
    } elseif (Test-Path "C:\Program Files\nu\bin\nu.exe") {
        $nuExePath = "C:\Program Files\nu\bin\nu.exe"
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\nu\bin\nu.exe") {
        $nuExePath = "$env:LOCALAPPDATA\Programs\nu\bin\nu.exe"
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\nu\nu.exe") {
        $nuExePath = "$env:LOCALAPPDATA\Programs\nu\nu.exe"
    } else {
        $nuExePath = "nu.exe"
    }

    $fragmentDir = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\nu"
    if (-not (Test-Path $fragmentDir)) {
        New-Item -Path $fragmentDir -ItemType Directory -Force | Out-Null
    }
    $nuIconPath = if (Test-Path "C:\Program Files\nu\nu.ico") { "C:\Program Files\nu\nu.ico" } else { "" }
    $fragmentObj = [PSCustomObject]@{
        profiles = @(
            [PSCustomObject]@{
                guid              = "{47302f9c-1ac4-566c-aa3e-8cf29889d6ab}"
                name              = "Nushell"
                commandline       = "`"$nuExePath`""
                icon              = $nuIconPath
                startingDirectory = "%USERPROFILE%"
            }
        )
    }
    $fragmentJson = $fragmentObj | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $fragmentDir "nu.json"), $fragmentJson, [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Nushell dynamic profile fragment verified: $(Join-Path $fragmentDir 'nu.json')" -ForegroundColor Green

    $templateJson = Get-Content -Path $SrcPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (Test-Path $DestPath) {
        $backupPath = "$($DestPath).bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host ">> Backing up existing settings.json -> $backupPath" -ForegroundColor Gray
        Copy-Item -Path $DestPath -Destination $backupPath -Force

        try {
            $destJson = Get-Content -Path $DestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warning "Existing settings.json could not be parsed. Overwriting with template."
            $destJson = $templateJson
        }

        # defaultProfile を Nushell ({47302f9c-1ac4-566c-aa3e-8cf29889d6ab}) に設定
        $destJson.defaultProfile = "{47302f9c-1ac4-566c-aa3e-8cf29889d6ab}"

        # profiles.defaults をテンプレートから適用（フォントやカラースキームなど）
        if (-not $destJson.profiles) {
            $destJson | Add-Member -MemberType NoteProperty -Name "profiles" -Value ([PSCustomObject]@{}) -Force
        }
        $destJson.profiles.defaults = $templateJson.profiles.defaults

        # profiles.list 内のプロファイルを整理（WSL/SSHなどの既存プロファイルを維持しつつNushellを確保）
        if ($destJson.profiles.list) {
            $existingProfiles = @($destJson.profiles.list)
            # 過去の不正な GUID や重複プロファイルをクリーンアップ
            $filteredProfiles = $existingProfiles | Where-Object {
                $_.guid -ne "{a5b8f673-9821-4a57-b248-73b320875e53}" -and
                -not ($_.name -eq "Nushell" -and $_.guid -ne "{47302f9c-1ac4-566c-aa3e-8cf29889d6ab}")
            }
            
            $nuProfile = $filteredProfiles | Where-Object { $_.guid -eq "{47302f9c-1ac4-566c-aa3e-8cf29889d6ab}" } | Select-Object -First 1
            if (-not $nuProfile) {
                $nuProfileEntry = [PSCustomObject]@{
                    guid   = "{47302f9c-1ac4-566c-aa3e-8cf29889d6ab}"
                    hidden = $false
                    name   = "Nushell"
                    source = "nu"
                }
                $filteredProfiles = @($nuProfileEntry) + $filteredProfiles
            } else {
                $nuProfile.hidden = $false
                $nuProfile.name = "Nushell"
            }
            $destJson.profiles.list = @($filteredProfiles)
        } else {
            $destJson.profiles.list = $templateJson.profiles.list
        }

        # schemes のマージ
        if (-not $destJson.schemes) {
            $destJson | Add-Member -MemberType NoteProperty -Name "schemes" -Value @() -Force
        }
        $existingSchemes = @($destJson.schemes)
        foreach ($tScheme in $templateJson.schemes) {
            $found = $existingSchemes | Where-Object { $_.name -eq $tScheme.name } | Select-Object -First 1
            if (-not $found) {
                $existingSchemes += $tScheme
            }
        }
        $destJson.schemes = @($existingSchemes)

        # actions / keybindings のマージ
        if ($templateJson.actions) {
            if (-not $destJson.actions) {
                $destJson | Add-Member -MemberType NoteProperty -Name "actions" -Value @() -Force
            }
            $existingActions = @($destJson.actions)
            foreach ($tAct in $templateJson.actions) {
                $found = $existingActions | Where-Object { $_.command -eq $tAct.command -or $_.keys -eq $tAct.keys } | Select-Object -First 1
                if (-not $found) {
                    $existingActions += $tAct
                }
            }
            $destJson.actions = @($existingActions)
        }

        $destJson.theme = "dark"

        $mergedJson = $destJson | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($DestPath, $mergedJson, [System.Text.Encoding]::UTF8)
        Write-Host "[OK] Windows Terminal settings merged & applied: $DestPath" -ForegroundColor Green
    } else {
        Copy-Item -Path $SrcPath -Destination $DestPath -Force
        Write-Host "[OK] Windows Terminal settings copied: $DestPath" -ForegroundColor Green
    }
}

# 1. Windows Terminal 設定のマージ配置
Deploy-WindowsTerminalConfig -SrcPath (Join-Path $configsDir "windows-terminal\settings.json") -DestPath $wtDest

# 2. その他 CLI / エディタ設定ファイルの配備マッピング
$deployTargets = @(
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
