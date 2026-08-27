#Requires -Version 5.1
<#
.SYNOPSIS
    winget を使用してモダン開発環境のツール・ランタイム・アプリケーションを一括インストールします。
.DESCRIPTION
    CLI、ターミナル、エディタ、ランタイム、各種ユーティリティをカテゴリ別に管理し、
    必要に応じてカテゴリごとのフィルタ実行も可能です。
#>
[CmdletBinding()]
param(
    [string[]]$Categories = @("All")
)

$ErrorActionPreference = "Continue"

# UTF-8 出力エンコーディングの設定（文字化け防止）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- パッケージ定義（カテゴリ別） ---
$packageGroups = [ordered]@{
    "Terminal" = @(
        @{ Id = "Microsoft.WindowsTerminal"; Name = "Windows Terminal" }
        @{ Id = "Nushell.Nushell";           Name = "Nushell (モダン構造化シェル)" }
        @{ Id = "Microsoft.PowerShell";      Name = "PowerShell 7 (pwsh)" }
    )

    "CLI_Tools" = @(
        @{ Id = "Starship.Starship";         Name = "Starship (高速クロスシェルプロンプト)" }
        @{ Id = "ajeetdsouza.zoxide";        Name = "zoxide (スマートcdコマンド)" }
        @{ Id = "eza-community.eza";         Name = "eza (モダンls)" }
        @{ Id = "sharkdp.bat";               Name = "bat (シンタックスハイライト付きcat)" }
        @{ Id = "BurntSushi.ripgrep.MSVC";   Name = "ripgrep (超高速grep)" }
        @{ Id = "sharkdp.fd";                Name = "fd (シンプル・高速find)" }
        @{ Id = "chmln.sd";                  Name = "sd (超高速正規表現置換/sed代替)" }
        @{ Id = "ast-grep.ast-grep";         Name = "ast-grep (AST構造コード検索・リファクタ)" }
        @{ Id = "jqlang.jq";                 Name = "jq (超高速JSONプロセッサ)" }
        @{ Id = "junegunn.fzf";              Name = "fzf (汎用ファジーファインダー)" }
        @{ Id = "JesseDuffield.lazygit";     Name = "lazygit (TUI Gitクライアント)" }
        @{ Id = "dandavison.delta";          Name = "delta (構文ハイライト付きdiffビューア)" }
        @{ Id = "Casey.Just";                Name = "just (モダンタスクランナー/make代替)" }
        @{ Id = "Clement.bottom";            Name = "bottom (TUIシステムモニタ/btm)" }
        @{ Id = "bootandy.dust";             Name = "dust (直感的なディレクトリ容量可視化)" }
        @{ Id = "muesli.duf";                Name = "duf (ディスク使用量一覧表示)" }
        @{ Id = "dbrgn.tealdeer";            Name = "tealdeer (高速tldr/チートシート)" }
        @{ Id = "sharkdp.hyperfine";         Name = "hyperfine (CLIベンチマークツール)" }
        @{ Id = "hdosys.herdr-win";          Name = "Herdr (AI TUIマルチプレクサ)" }
        @{ Id = "Microsoft.Coreutils";       Name = "uutils coreutils (Rust製GNUコア)" }
        @{ Id = "uutils.diffutils";          Name = "uutils diffutils (Rust製diff/cmp)" }
        @{ Id = "Wilfred.difftastic";        Name = "difftastic (AST構文木Diffビューア/difft)" }
        @{ Id = "ducaale.xh";                Name = "xh (超高速HTTP/APIクライアント/curl代替)" }
        @{ Id = "dalance.procs";             Name = "procs (超高速プロセスビューア/ps代替)" }
        @{ Id = "sharkdp.hexyl";             Name = "hexyl (色分けバイナリ/Hexビューア)" }
        @{ Id = "charmbracelet.glow";        Name = "glow (ターミナルMarkdownリッチレンダラー)" }
        @{ Id = "hpjansson.Chafa";           Name = "Chafa (超高速ターミナル画像/Sixelレンダラー)" }
    )

    "Editors_DevTools" = @(
        @{ Id = "Helix.Helix";               Name = "Helix (モダンモーダルエディタ)" }
        @{ Id = "Anysphere.Cursor";          Name = "Cursor (AI駆動コードエディタ)" }
        @{ Id = "Git.Git";                   Name = "Git" }
        @{ Id = "GitHub.cli";                Name = "GitHub CLI (gh)" }
        @{ Id = "Google.AntigravityCLI";     Name = "Google Antigravity CLI" }
        @{ Id = "Fly-io.flyctl";             Name = "Fly.io CLI" }
        @{ Id = "Bruno.Bruno";               Name = "Bruno (軽量・オフラインAPIクライアント)" }
    )

    "Runtimes_Formatters" = @(
        @{ Id = "astral-sh.uv";              Name = "uv (超高速Pythonパッケージ/ランタイムマネージャー)" }
        @{ Id = "Schniz.fnm";                Name = "fnm (Rust製 高速Node.jsバージョンマネージャー)" }
        @{ Id = "pnpm.pnpm";                 Name = "pnpm (高速・省ディスクNodeパッケージマネージャー)" }
        @{ Id = "Oven-sh.Bun";               Name = "Bun (オールインワンJS/TSランタイム)" }
        @{ Id = "Rustlang.Rustup";           Name = "Rustup (Rustツールチェーン)" }
        @{ Id = "BiomeJS.Biome";             Name = "Biome (超高速JS/TSフォーマッター・リンター)" }
        @{ Id = "tamasfe.taplo";             Name = "Taplo (TOML LSP・フォーマッター)" }
    )

    "Utilities" = @(
        @{ Id = "Gyan.FFmpeg";               Name = "FFmpeg (動画・音声処理)" }
        @{ Id = "libvips.libvips";           Name = "libvips (高速画像処理ライブラリ)" }
        @{ Id = "7zip.7zip";                 Name = "7-Zip" }
        @{ Id = "Microsoft.PowerToys";       Name = "PowerToys (Windows拡張機能群)" }
        @{ Id = "Bitwarden.Bitwarden";       Name = "Bitwarden (パスワード管理)" }
        @{ Id = "QL-Win.QuickLook";          Name = "QuickLook (Spaceキー即時プレビュー)" }
        @{ Id = "voidtools.Everything";      Name = "Everything (超高速ファイル検索)" }
    )

    "Apps" = @(
        @{ Id = "Google.Chrome";             Name = "Google Chrome" }
        @{ Id = "Discord.Discord";           Name = "Discord" }
        @{ Id = "SlackTechnologies.Slack";   Name = "Slack" }
        @{ Id = "9NCBCSZSJRSB";              Name = "Spotify"; Source = "msstore" }
        @{ Id = "ByteDance.CapCut";          Name = "CapCut" }
        @{ Id = "Valve.Steam";               Name = "Steam" }
    )
}

function Install-WingetPackage {
    param (
        [string]$Id,
        [string]$Name,
        [string]$Source = ""
    )

    Write-Host "`n>> [winget] Installing $Name ($Id)..." -ForegroundColor Cyan
    $sourceArgs = if ($Source) { @("-s", $Source) } else { @() }
    $result = winget install --id $Id -e --silent --accept-source-agreements --accept-package-agreements @sourceArgs 2>&1

    $alreadyInstalledCodes = @(
        -1978335189, # 0x8A15002B: WINGET_INSTALLED_PACKAGE_ALREADY_INSTALLED
        -1978335188, # 0x8A15002C: WINGET_INSTALL_UPGRADE_NOT_APPLICABLE
        -1978335216  # 0x8A150010: WINGET_SOURCE_NO_UPDATE
    )

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $Name installed successfully." -ForegroundColor Green
    } elseif ($alreadyInstalledCodes -contains $LASTEXITCODE) {
        Write-Host "[SKIP] $Name is already installed / up to date." -ForegroundColor Yellow
    } elseif ($LASTEXITCODE -eq -1978335146) {
        # 0x8A150056: APPINSTALLER_CLI_ERROR_INSTALLER_PROHIBITS_ELEVATION (管理者コンテキスト禁止パッケージ)
        # セキュリティ強化: ハッシュ未検証の直接バイナリダウンロードを排除し、winget スコープ指定で再試行
        Write-Host ">> [Retry] Elevated context detected for $Name. Attempting install with user scope..." -ForegroundColor Cyan
        $retryResult = winget install --id $Id -e --silent --accept-source-agreements --accept-package-agreements --scope user @sourceArgs 2>&1
        if ($LASTEXITCODE -eq 0 -or ($alreadyInstalledCodes -contains $LASTEXITCODE)) {
            Write-Host "[OK] $Name installed successfully with user scope." -ForegroundColor Green
        } else {
            Write-Warning "[NOTICE] $Name ($Id) prohibits elevated installation. Please run 'winget install --id $Id' in a normal non-admin terminal."
        }
    } else {
        Write-Warning "[WARN] $Name ($Id) returned exit code: $LASTEXITCODE"
        if ($result) {
            $result | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
        }
    }
}

# --- 実行処理 ---
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "  Step 1: Winget Package Installation     " -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta

# winget の存在確認
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget が見つかりません。App Installer をインストールしてください。"
    exit 1
}

$runAll = $Categories -contains "All"

foreach ($groupKey in $packageGroups.Keys) {
    if ($runAll -or ($Categories -contains $groupKey)) {
        Write-Host "`n--- Category: $groupKey ---" -ForegroundColor Blue
        foreach ($pkg in $packageGroups[$groupKey]) {
            $src = if ($pkg.ContainsKey("Source")) { $pkg["Source"] } else { "" }
            Install-WingetPackage -Id $pkg.Id -Name $pkg.Name -Source $src
        }
    }
}

Write-Host "`n[DONE] Winget package installation step finished." -ForegroundColor Green
