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
    - Herdr プラグイン (herdr-sidebar) の導入
    - Cursor Agent CLI (agent / cursor-agent) の自動導入
    - AI Agent 安全環境変数 & ~/.local/bin シム構築
#>
[CmdletBinding()]
param(
    [switch]$OnlyRtk,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

# UTF-8 出力エンコーディングの設定（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot "Assert-PinnedHash.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
$pinsPath = Join-Path $repoRoot "configs\pins.json"
$pins = Get-Content -Raw -Path $pinsPath | ConvertFrom-Json
$rtkPin = [string]$pins.rtk

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

function Install-RustupJaq {
    Write-Host "`n>> [4/11] Checking Rustup & Cargo Tools..." -ForegroundColor Cyan
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

function Install-CursorRtkHook {
    $rtkExe = Join-Path (Join-Path $env:USERPROFILE ".local\bin") "rtk.exe"
    if (-not (Test-Path $rtkExe)) {
        $cmd = Get-Command rtk -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Warning "[WARN] rtk not found; skip Cursor hook init."
            return
        }
        $rtkExe = $cmd.Source
    }
    Write-Host "   Installing official Cursor rtk hook (rtk init -g --agent cursor --hook-only)..." -ForegroundColor Gray
    $hooksPath = Join-Path (Join-Path $env:USERPROFILE ".cursor") "hooks.json"
    if ((Test-Path $hooksPath) -and ((Get-Content -Raw -Path $hooksPath) -match 'agent_guard')) {
        Remove-Item -Path $hooksPath -Force
    }
    & $rtkExe init -g --agent cursor --hook-only --auto-patch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Cursor rtk hook installed." -ForegroundColor Green
    } else {
        Write-Warning "[WARN] rtk init failed (exit $LASTEXITCODE)."
    }
}

function Install-RtkCli {
    param([switch]$Force)
    Write-Host "`n>> [5/11] Checking RTK (Rust Token Killer - pinned v$rtkPin)..." -ForegroundColor Cyan
    $localBinDir = Join-Path $env:USERPROFILE ".local\bin"
    $rtkExe = Join-Path $localBinDir "rtk.exe"

    if (-not (Test-Path $localBinDir)) {
        New-Item -Path $localBinDir -ItemType Directory -Force | Out-Null
    }

    $currentVersion = $null
    if (Test-Path $rtkExe) {
        try {
            $verOutput = & $rtkExe --version 2>&1
            if ($LASTEXITCODE -eq 0 -and $verOutput -match "rtk\s+([\d\.]+)") {
                $currentVersion = $Matches[1]
            }
        } catch {
            $currentVersion = $null
        }
    }

    if ($currentVersion -eq $rtkPin -and -not $Force) {
        Write-Host "[OK] RTK is at pin v$rtkPin." -ForegroundColor Green
        Install-CursorRtkHook
        return
    }

    $tag = "v$rtkPin"
    Write-Host "   Downloading RTK binary ($tag) from GitHub releases..." -ForegroundColor Gray
    $installed = $false
    try {
        $releaseApi = "https://api.github.com/repos/rtk-ai/rtk/releases/tags/$tag"
        $release = Invoke-RestMethod -Uri $releaseApi -UseBasicParsing -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -like "*x86_64-pc-windows-msvc.zip" } | Select-Object -First 1
        if ($asset) {
            $downloadUrl = $asset.browser_download_url
            if (-not ($downloadUrl -match '^https://(?:github\.com/rtk-ai/rtk/releases/download/|objects\.githubusercontent\.com/)')) {
                throw "Security validation failed: Invalid download URL domain for RTK release ($downloadUrl)"
            }
            $tempZip = Join-Path $env:TEMP "rtk_pinned.zip"
            $tempExtract = Join-Path $env:TEMP "rtk_extract"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
            if (-not (Test-Path $tempZip) -or (Get-Item $tempZip).Length -lt 100000) {
                throw "Security validation failed: Downloaded RTK package is missing or corrupted."
            }
            $rtkSha256 = (Get-FileHash -Path $tempZip -Algorithm SHA256).Hash
            Write-Host "   [SHA256] RTK: $rtkSha256" -ForegroundColor DarkGray
            Assert-PinnedHash -Name "rtk:$tag" -FilePath $tempZip
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
            $extractedExe = Get-ChildItem -Path $tempExtract -Filter "rtk.exe" -Recurse | Select-Object -First 1
            if ($extractedExe) {
                Copy-Item -Path $extractedExe.FullName -Destination $rtkExe -Force
                Remove-Item -Path $tempZip, $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
                $newVer = & $rtkExe --version 2>&1
                Write-Host "[OK] RTK binary installed: $newVer (pin $tag)" -ForegroundColor Green
                $installed = $true
            }
        }
    } catch {
        if ("$_" -match 'SHA256') { throw }
        Write-Warning "[WARN] Failed to download pinned RTK release $tag : $_"
    }

    if (-not $installed -and (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Host "   Building RTK $tag from source via cargo..." -ForegroundColor Gray
        try {
            cargo install --git https://github.com/rtk-ai/rtk --tag $tag --locked 2>&1 | Out-Null
            $cargoRtk = Join-Path $env:USERPROFILE ".cargo\bin\rtk.exe"
            if (Test-Path $cargoRtk) {
                Copy-Item -Path $cargoRtk -Destination $rtkExe -Force
                Write-Host "[OK] RTK $tag built and installed via cargo." -ForegroundColor Green
                $installed = $true
            }
        } catch {
            Write-Warning "[WARN] Failed to build RTK via cargo: $_"
        }
    }

    Install-CursorRtkHook
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
            if (-not ($pkgUrl -match '^https://(?:downloads\.cursor\.com|(?:[a-zA-Z0-9-]+\.)*cursor\.sh)/')) {
                throw "Security validation failed: Invalid download domain for Cursor Agent CLI package ($pkgUrl)"
            }
            curl.exe -fsSL -o $tempZip $pkgUrl
            if (-not (Test-Path $tempZip) -or (Get-Item $tempZip).Length -lt 1000000) {
                throw "Security validation failed: Downloaded Cursor Agent CLI package is missing or corrupted."
            }
            $cursorSha256 = (Get-FileHash -Path $tempZip -Algorithm SHA256).Hash
            Write-Host "   [SHA256] Cursor Agent CLI: $cursorSha256" -ForegroundColor DarkGray
            Assert-PinnedHash -Name "cursor-agent:$version" -FilePath $tempZip
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
        if ("$_" -match 'SHA256') { throw }
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
        "RTK_TELEMETRY_DISABLED"      = "1"
        "RTK_SKIP_ENV"                = "1"
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

    # fnm default node shims (provides permanent node/npm/npx/corepack fallback in ~/.local/bin for all shells & IDEs)
    $fnmDefaultDir = "$env:APPDATA\fnm\aliases\default"
    if (-not (Test-Path (Join-Path $fnmDefaultDir "node.exe"))) {
        $fnmVersionsDir = "$env:APPDATA\fnm\node-versions"
        if (Test-Path $fnmVersionsDir) {
            $latestNode = Get-ChildItem -Path $fnmVersionsDir -Directory | Where-Object { $_.Name -like "v*" } | Sort-Object Name -Descending | Select-Object -First 1
            if ($latestNode) {
                $fnmDefaultDir = Join-Path $latestNode.FullName "installation"
            }
        }
    }

    if (Test-Path (Join-Path $fnmDefaultDir "node.exe")) {
        # Copy standalone node.exe
        $nodeDest = Join-Path $localBinDir "node.exe"
        if (Test-Path $nodeDest) { Remove-Item $nodeDest -Force -ErrorAction SilentlyContinue }
        Copy-Item -Path (Join-Path $fnmDefaultDir "node.exe") -Destination $nodeDest -Force -ErrorAction SilentlyContinue | Out-Null

        # Create forwarder wrappers for npm, npx, corepack so %~dp0 relative path to node_modules is preserved
        foreach ($tool in @("npm", "npx", "corepack")) {
            $cmdPath = Join-Path $localBinDir "$tool.cmd"
            $ps1Path = Join-Path $localBinDir "$tool.ps1"
            if (Test-Path $cmdPath) { Remove-Item $cmdPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path $ps1Path) { Remove-Item $ps1Path -Force -ErrorAction SilentlyContinue }

            $cmdContent = "@echo off`r`nif exist `"%APPDATA%\fnm\aliases\default\$tool.cmd`" (`r`n  `"%APPDATA%\fnm\aliases\default\$tool.cmd`" %*`r`n) else (`r`n  echo [ERROR] Node.js / $tool not found in fnm default installation. >&2`r`n  exit /b 1`r`n)"
            $ps1Content = "`$target = `"`$env:APPDATA\fnm\aliases\default\$tool.cmd`"`r`nif (Test-Path `$target) {`r`n    & `$target @args`r`n} else {`r`n    Write-Error `"$tool could not be resolved from fnm default installation.`"`r`n    exit 1`r`n}"

            Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII -Force
            Set-Content -Path $ps1Path -Value $ps1Content -Encoding ASCII -Force
        }
    }

    # Cursor Agent CLI resilient wrappers in ~/.local/bin (delegates execution to %LOCALAPPDATA%\cursor-agent to find index.js)
    $cursorAgentCmd = "$env:LOCALAPPDATA\cursor-agent\cursor-agent.cmd"
    $agentCmd = "$env:LOCALAPPDATA\cursor-agent\agent.cmd"
    if (Test-Path $agentCmd) {
        "@echo off`r`n`"$cursorAgentCmd`" %*" | Set-Content -Path (Join-Path $localBinDir "cursor-agent.cmd") -Encoding ASCII
        "@echo off`r`n`"$agentCmd`" %*" | Set-Content -Path (Join-Path $localBinDir "agent.cmd") -Encoding ASCII
        "& `"$cursorAgentCmd`" @args" | Set-Content -Path (Join-Path $localBinDir "cursor-agent.ps1") -Encoding ASCII
        "& `"$agentCmd`" @args" | Set-Content -Path (Join-Path $localBinDir "agent.ps1") -Encoding ASCII
    }

    $shimSourceDirs = @(
        "C:\Program Files\coreutils\bin",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$env:USERPROFILE\.cargo\bin"
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
            $exes = Get-ChildItem -Path "$srcDir\*" -Include "*.exe", "*.cmd", "*.ps1" -File -ErrorAction SilentlyContinue
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
    Write-Host "[OK] Modern CLI, Coreutils, and Node shims verified in $localBinDir." -ForegroundColor Green
}

if ($OnlyRtk) {
    Install-RtkCli -Force:$Force
    Write-Host "`n[DONE] RTK setup completed." -ForegroundColor Green
    return
}

# --- 順次実行 ---
Install-FnmNode
Install-UvPython
Install-RustupJaq
Install-RtkCli -Force:$Force
Update-TealdeerCache
Install-HunkMermaid
Install-HerdrPlugins
Install-CursorAgentCli
Set-AgentSafetyEnvironmentVariables
Build-LocalBinShims

Write-Host "`n[DONE] Runtime setup step finished." -ForegroundColor Green
