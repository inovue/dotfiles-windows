#Requires -Version 5.1
<#
.SYNOPSIS
    インストールされたランタイム・CLIツールの初期化・セットアップを行います。
.DESCRIPTION
    - fnm による Node.js (LTS) の自動インストール
    - uv による Python ランタイムの自動導入
    - rustup の初期設定
    - tealdeer (tldr) のキャッシュ更新
    - Hunk (hunkdiff) & Mermaid-ASCII CLI の導入
    - Graphify (知識グラフ CLI / AI スキル) の導入
    - Herdr プラグイン (herdr-sidebar) の導入
    - Cursor Agent CLI (agent / cursor-agent) の自動導入
    - AI Agent 安全環境変数 & ~/.local/bin シム構築
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

function Install-FnmNode {
    Write-Host "`n>> [1/10] Setting up fnm (Fast Node Manager)..." -ForegroundColor Cyan
    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        try {
            Write-Host "   Installing Node.js LTS via fnm..." -ForegroundColor Gray
            fnm install --lts
            fnm default lts-latest
            fnm env --use-on-cd | Out-String | Invoke-Expression
            Write-Host "[OK] Node.js LTS is set as default." -ForegroundColor Green
        } catch {
            Write-Warning "[WARN] Failed to configure fnm: $_"
        }
    } else {
        Write-Host "[SKIP] fnm is not in PATH yet. Restarting terminal might be required." -ForegroundColor Yellow
    }
}

function Install-UvPython {
    Write-Host "`n>> [2/10] Setting up uv (Python Manager)..." -ForegroundColor Cyan
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        try {
            Write-Host "   Installing latest stable Python via uv..." -ForegroundColor Gray
            uv python install 3.12 3.13
            Write-Host "[OK] Python 3.12/3.13 installed via uv." -ForegroundColor Green

            Write-Host "   Installing/Verifying playwright for browser-agent..." -ForegroundColor Gray
            uv pip install --system playwright 2>&1 | Out-Null
            if (-not $?) {
                pip install playwright 2>&1 | Out-Null
            }
            Write-Host "[OK] Playwright installed for browser-agent." -ForegroundColor Green
        } catch {
            Write-Warning "[WARN] Failed to configure uv: $_"
        }
    } else {
        Write-Host "[SKIP] uv is not in PATH yet." -ForegroundColor Yellow
    }
}

function Install-GraphifyCli {
    Write-Host "`n>> [3/10] Setting up Graphify (uv tool)..." -ForegroundColor Cyan
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        try {
            $graphifyPresent = $false
            try {
                $toolList = uv tool list 2>&1 | Out-String
                $graphifyPresent = ($toolList -match '(?m)^graphifyy\b')
            } catch { }

            $extras = "graphifyy[mcp,gemini,openai,anthropic]"

            if ($graphifyPresent) {
                Write-Host "   graphifyy already installed; ensuring full LLM extras in virtualenv..." -ForegroundColor Gray
                $graphifyVenv = Join-Path $env:APPDATA "uv\tools\graphifyy"
                if (Test-Path $graphifyVenv) {
                    uv pip install --python $graphifyVenv openai 2>&1 | Out-Null
                }
            } else {
                Write-Host "   Installing $extras via uv tool (CLI: graphify / graphify-mcp)..." -ForegroundColor Gray
                uv tool install $extras 2>&1 | Out-Null
            }

            $uvToolBin = ""
            try { $uvToolBin = (uv tool dir --bin 2>$null).Trim() } catch { }
            if (-not $uvToolBin) { $uvToolBin = Join-Path $env:USERPROFILE ".local\bin" }
            if ($env:Path -notlike "*$uvToolBin*") { $env:Path = "$uvToolBin;$env:Path" }

            if ((Get-Command graphify -ErrorAction SilentlyContinue) -and (Get-Command graphify-mcp -ErrorAction SilentlyContinue)) {
                Write-Host "[OK] graphify + graphify-mcp installed with LLM backends." -ForegroundColor Green
            } else {
                Write-Warning "[WARN] graphify binary not found after uv tool install. Restart terminal or check PATH ($uvToolBin)."
            }
        } catch {
            Write-Warning "[WARN] Failed to install/configure graphify: $_"
        }
    } else {
        Write-Host "[SKIP] uv is not in PATH yet (required for graphify)." -ForegroundColor Yellow
    }
}

function Install-RustupJaq {
    Write-Host "`n>> [4/10] Checking Rustup & Cargo Tools..." -ForegroundColor Cyan
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        try {
            Write-Host "   Setting default Rust toolchain to stable..." -ForegroundColor Gray
            rustup default stable
            Write-Host "[OK] Rust stable toolchain configured." -ForegroundColor Green

            if (-not (Get-Command jaq -ErrorAction SilentlyContinue)) {
                Write-Host "   Installing jaq (Rust high-speed JSON processor) via cargo..." -ForegroundColor Gray
                cargo install jaq --locked 2>&1 | Out-Null
                Write-Host "[OK] jaq installed via cargo." -ForegroundColor Green
            } else {
                Write-Host "[OK] jaq is already installed." -ForegroundColor Green
            }
        } catch {
            Write-Warning "[WARN] Failed to configure rustup/cargo: $_"
        }
    } else {
        Write-Host "[SKIP] rustup is not in PATH yet." -ForegroundColor Yellow
    }
}

function Update-TealdeerCache {
    Write-Host "`n>> [5/10] Updating tealdeer (tldr) cache..." -ForegroundColor Cyan
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
}

function Install-HunkMermaid {
    Write-Host "`n>> [6/10] Installing Hunk (hunkdiff) & Mermaid-ASCII..." -ForegroundColor Cyan
    try {
        if (Get-Command bun -ErrorAction SilentlyContinue) {
            Write-Host "   Installing hunkdiff and mermaid-ascii via bun..." -ForegroundColor Gray
            bun add -g hunkdiff mermaid-ascii 2>&1 | Out-Null
            Write-Host "[OK] hunkdiff and mermaid-ascii installed via bun." -ForegroundColor Green
        } elseif (Get-Command pnpm -ErrorAction SilentlyContinue) {
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
            Write-Host "   Installing hunkdiff & mermaid-ascii via pnpm..." -ForegroundColor Gray
            pnpm add -g hunkdiff mermaid-ascii
            Write-Host "[OK] hunkdiff and mermaid-ascii installed via pnpm." -ForegroundColor Green
        } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
            Write-Host "   Installing hunkdiff & mermaid-ascii via npm..." -ForegroundColor Gray
            npm install -g hunkdiff mermaid-ascii
            Write-Host "[OK] hunkdiff and mermaid-ascii installed via npm." -ForegroundColor Green
        } else {
            Write-Host "[SKIP] Node/Bun package manager not in PATH yet." -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "[WARN] Failed to install CLI utilities: $_"
    }
}

function Install-HerdrPlugins {
    Write-Host "`n>> [7/10] Checking Herdr Plugins (herdr-sidebar)..." -ForegroundColor Cyan
    if (Get-Command herdr -ErrorAction SilentlyContinue) {
        try {
            $pluginList = herdr plugin list 2>&1 | Out-String
            if ($pluginList -notmatch "herdr-sidebar") {
                Write-Host "   Installing herdr-sidebar plugin from alexarthurs/herdr-sidebar..." -ForegroundColor Gray
                herdr plugin install alexarthurs/herdr-sidebar/plugins/herdr-sidebar --yes 2>&1 | Out-Null
                Write-Host "[OK] herdr-sidebar plugin installed successfully." -ForegroundColor Green
            } else {
                Write-Host "[OK] herdr-sidebar plugin is already installed." -ForegroundColor Green
            }
        } catch {
            Write-Warning "[WARN] Failed to install/verify herdr-sidebar plugin: $_"
        }
    } else {
        Write-Host "[SKIP] herdr is not in PATH yet." -ForegroundColor Yellow
    }
}

function Install-CursorAgentCli {
    Write-Host "`n>> [8/10] Setting up Cursor Agent CLI (agent / cursor-agent)..." -ForegroundColor Cyan
    try {
        $agentPath = "$env:LOCALAPPDATA\cursor-agent"
        $versionsPath = "$agentPath\versions"
        $agentExe = "$agentPath\agent.cmd"

        $needsInstall = $false
        if (-not (Test-Path $agentExe)) {
            $needsInstall = $true
        }

        if ($needsInstall) {
            Write-Host "   Downloading and installing Cursor Agent CLI..." -ForegroundColor Gray
            $tempZip = "$env:TEMP\cursor-agent.zip"
            $installScript = curl.exe -fsSL "https://cursor.com/install?win32=true" 2>&1 | Out-String
            
            $downloadUrl = "https://downloads.cursor.com/lab/2026.08.11-e8db854/"
            $version = "2026.08.11-e8db854"
            if ($installScript -match '\$downloadUrl\s*=\s*''([^'']+)''') { $downloadUrl = $matches[1] }
            if ($installScript -match '\$version\s*=\s*''([^'']+)''') { $version = $matches[1] }

            if (-not (Test-Path $versionsPath)) {
                New-Item -ItemType Directory -Path $versionsPath -Force | Out-Null
            }

            $pkgUrl = "${downloadUrl}windows/x64/agent-cli-package.zip"
            if (-not ($pkgUrl -match '^https://(?:downloads\.cursor\.com|.*\.cursor\.sh)/')) {
                throw "Security validation failed: Invalid download domain for Cursor Agent CLI package ($pkgUrl)"
            }
            curl.exe -fsSL -o $tempZip $pkgUrl
            if (-not (Test-Path $tempZip) -or (Get-Item $tempZip).Length -lt 1000000) {
                throw "Security validation failed: Downloaded Cursor Agent CLI package is missing or corrupted."
            }
            Expand-Archive -Path $tempZip -DestinationPath $versionsPath -Force

            $distPackagePath = Join-Path $versionsPath "dist-package"
            $versionPath = Join-Path $versionsPath $version
            if (Test-Path $distPackagePath) {
                Rename-Item -Path $distPackagePath -NewName $version -Force -ErrorAction SilentlyContinue
            }

            Get-ChildItem -Path $versionPath -Filter "cursor-agent*" | Copy-Item -Destination $agentPath -Force
            if (Test-Path "$agentPath\cursor-agent.exe") { Copy-Item -Path "$agentPath\cursor-agent.exe" -Destination "$agentPath\agent.exe" -Force }
            if (Test-Path "$agentPath\cursor-agent.cmd") { Copy-Item -Path "$agentPath\cursor-agent.cmd" -Destination "$agentPath\agent.cmd" -Force }
            if (Test-Path "$agentPath\cursor-agent.ps1") { Copy-Item -Path "$agentPath\cursor-agent.ps1" -Destination "$agentPath\agent.ps1" -Force }

            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Cursor Agent CLI installed successfully ($version)." -ForegroundColor Green
        } else {
            Write-Host "[OK] Cursor Agent CLI is already installed." -ForegroundColor Green
        }

        $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentUserPath -notlike "*$agentPath*") {
            [System.Environment]::SetEnvironmentVariable("Path", "$agentPath;$currentUserPath", "User")
        }
        if ($env:Path -notlike "*$agentPath*") {
            $env:Path = "$agentPath;$env:Path"
        }
    } catch {
        Write-Warning "[WARN] Failed to configure Cursor Agent CLI: $_"
    }
}

function Set-AgentSafetyEnvironmentVariables {
    Write-Host "`n>> [9/10] Configuring AI Agent Safety & Performance Environment Variables..." -ForegroundColor Cyan
    $envVarsToSet = @{
        "PAGER"                       = "cat"
        "BAT_PAGER"                   = ""
        "BAT_STYLE"                   = "plain"
        "GIT_PAGER"                   = "cat"
        "DELTA_PAGER"                 = "cat"
        "PYTHONUTF8"                  = "1"
        "POWERSHELL_TELEMETRY_OPTOUT" = "1"
        "DOTNET_CLI_TELEMETRY_OPTOUT" = "1"
    }
    foreach ($key in $envVarsToSet.Keys) {
        $val = $envVarsToSet[$key]
        [System.Environment]::SetEnvironmentVariable($key, $val, "User")
        Set-Item -Path "env:$key" -Value $val
    }
    Write-Host "[OK] Agent non-interactive pager bypass & UTF-8 variables set in User scope." -ForegroundColor Green
}

function Build-LocalBinShims {
    Write-Host "`n>> [10/10] Setting up ~/.local/bin shim directory in PATH..." -ForegroundColor Cyan
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

    $shimSourceDirs = @(
        "C:\Program Files\coreutils\bin",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$env:USERPROFILE\.cargo\bin",
        "$env:LOCALAPPDATA\cursor-agent"
    )

    $wingetPkgDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path $wingetPkgDir) {
        $foundExes = Get-ChildItem -Path $wingetPkgDir -Recurse -Include "ast-grep.exe", "sg.exe", "sd.exe", "difft.exe", "xh.exe", "procs.exe", "hexyl.exe", "Chafa.exe", "chafa.exe", "glow.exe" -ErrorAction SilentlyContinue
        foreach ($f in $foundExes) {
            $shimPath = Join-Path $localBinDir $f.Name
            if (-not (Test-Path $shimPath)) {
                Copy-Item -Path $f.FullName -Destination $shimPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    foreach ($srcDir in $shimSourceDirs) {
        if (Test-Path $srcDir) {
            $exes = Get-ChildItem -Path $srcDir -Include "*.exe", "*.cmd" -File -ErrorAction SilentlyContinue
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
}

# --- 順次実行 ---
Install-FnmNode
Install-UvPython
Install-GraphifyCli
Install-RustupJaq
Update-TealdeerCache
Install-HunkMermaid
Install-HerdrPlugins
Install-CursorAgentCli
Set-AgentSafetyEnvironmentVariables
Build-LocalBinShims

Write-Host "`n[DONE] Runtime setup step finished." -ForegroundColor Green
