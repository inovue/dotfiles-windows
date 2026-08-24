# dotfiles-windows

Nushell、Helix、Windows Terminal、および Rust/Go 製の高速モダン CLI ツールを中心とした Windows ネイティブ開発環境、ならびに **AI エージェント（Antigravity CLI, Cursor, Claude Code, Codex等）の超高速化・安定化** を実現する設定管理リポジトリです。

---

## 📂 ディレクトリ構成（責務の分離）

```
dotfiles-windows/
├── AGENTS.md                       # 🧭 AIエージェント向けプロジェクトナビゲーション＆実行SSOT
├── CLAUDE.md                       # Claude Code 用プロジェクトガイド（AGENTS.md同期）
├── .cursorrules                    # Cursor 用プロジェクトルール（AGENTS.md同期）
├── justfile                        # Just タスクランナー定義（sync-rules, deploy, test等）
├── install.ps1                     # 統合エントリポイント (全自動 or ステップ別実行)
├── README.md                       # ユーザー向けドキュメント
├── tests/
│   └── verify_tools.ps1            # 環境・モダンCLI・エージェント設定の網羅的自動テスト
├── scripts/
│   ├── 01_winget_packages.ps1      # 1. winget によるツール・アプリ一括導入
│   ├── 02_install_fonts.ps1        # 2. UDEV Gothic NF (日本語 + Nerd Fonts) 自動取得・登録
│   ├── 03_setup_runtimes.ps1       # 3. fnm / uv / Rust / jaq / Agent環境変数 / ~/.local/bin の初期化
│   ├── 04_setup_configs.ps1        # 4. Dotfiles & AI Agent SSOT ルールの自動配備
│   └── sync_agent_rules.ps1        # AI Agent ルール＆スキルの高速一括同期
└── configs/
    ├── agents/                     # 🌟 AIエージェント単一マスタールール (SSOT)
    │   ├── AGENTS.md               # グローバル共通ルール (CLI置換表, 非対話, UTF-8, ゼロハング)
    │   └── skills/                 # 段階的開示スキル (Progressive Disclosure)
    │       ├── browser-agent/      # 実Chrome・a11y・プロファイル自動化
    │       └── modern-cli-expert/  # ast-grep, sd, jaq, xh 高速レシピ
    ├── powershell/                 # PowerShell 設定 (非対話高速化, エイリアス解除, UTF-8)
    │   └── Microsoft.PowerShell_profile.ps1
    ├── windows-terminal/           # Windows Terminal 設定 (UDEV Gothic 35NF, Catppuccin, Nushell既定)
    │   └── settings.json
    ├── helix/                      # Helix 設定 (相対行番号, IME対策, Biome/Rust LSP連携)
    │   ├── config.toml
    │   └── languages.toml
    ├── nushell/                    # Nushell 設定 (Starship/zoxide連携, 高速モダンエイリアス)
    │   ├── config.nu
    │   └── env.nu
    ├── starship/starship.toml      # Starship 美麗プロンプト設定
    ├── lazygit/config.yml          # Lazygit + Delta 連携設定
    └── herdr/config.toml           # Herdr 設定 (Nushell既定, Catppuccin, IME対策)
```

---

## ⚡ クイックコマンド (`just`)

本リポジトリにはコマンドランナー `just` が設定されており、日常的な操作を1コマンドで実行できます。

| コマンド | 内容 |
| :--- | :--- |
| `just sync-rules` | 🌟 正本 (`configs/agents/`) から全エージェント・ワークスペースへルールを一括同期 |
| `just check-rules`| ルールが正本と同期されているか検証（差分チェック） |
| `just test` | CLIツール、環境変数、SSOTルールの網羅的自動テストを実行 |
| `just deploy` | 全設定ファイル（Dotfiles + Rules）をユーザー環境にデプロイ |
| `just install` | 環境構築（パッケージ、フォント、ランタイム、設定）を一括実行 |

---

## 🚀 使い方

PowerShell を **管理者権限** で開き、本ディレクトリに移動して実行します。

### 一括セットアップ（推奨）

```powershell
.\install.ps1 -All
# または
just install
```

> **シンボリックリンクで設定を同期したい場合**:
> ```powershell
> .\install.ps1 -All -UseSymlinks
> ```

---

### ステップごとの個別実行

必要なステップのみを個別に実行することも可能です。

| コマンド | 実行内容 |
| :--- | :--- |
| `.\install.ps1 -Step 1` | `winget` パッケージの一括インストール |
| `.\install.ps1 -Step 2` | `UDEV Gothic NF` (35NF) フォントの自動ダウンロード・登録 |
| `.\install.ps1 -Step 3` | ランタイム初期化、Agent環境変数 (`PAGER=cat`等)、`~/.local/bin` の構成 |
| `.\install.ps1 -Step 4` | 設定ファイル（Dotfiles）および AI Agent ルールの一括配備 (`just deploy`) |
| `.\scripts\sync_agent_rules.ps1` | AI Agent ルール＆スキルのみを高速一括同期 (`just sync-rules`) |

---

## 🤖 AI Agent 超高速化・安定化アーキテクチャ (SSOT)

本環境では、AIエージェント（Antigravity, Cursor, Claude Code, Codex）がWindows上で動作する際の遅延・ハングを徹底的に排除しています。

1. **二重管理ゼロの SSOT ルール**:
   - `configs/agents/AGENTS.md` を唯一のマスターとし、各エージェントのグローバル設定パス（`~/.gemini/config/AGENTS.md`, `~/.claude/CLAUDE.md`, `%APPDATA%\Cursor\User\AGENTS.md`）へ自動シンボリックリンク同期。
2. **ネイティブ高速CLIツールの優先**:
   - 重い PowerShell Cmdlet（`Get-Content`, `Select-String`, `ConvertFrom-Json`）をバイパスし、Rust/Go 製バイナリ（`rg`, `fd`, `sd`, `ast-grep`, `jq`, `bat`）を直接実行。
3. **非対話ハング・文字化けの完全防止**:
   - `PAGER=cat`, `BAT_PAGER=""`, `BAT_STYLE=plain`, `GIT_PAGER=cat`, `PYTHONUTF8=1` を永続化し、ページャー待ちやANSIエスケープ破綻を封殺。

---

## 🛠 主な同梱ツール一覧

- **Shell / Terminal**: Nushell, Windows Terminal, PowerShell 7 (`pwsh`)
- **Font**: UDEV Gothic 35NF (JetBrains Mono + BIZ UDゴシック + Nerd Fonts)
- **CLI Utilities (Rust/Go)**:
  - `Starship` (プロンプト) / `zoxide` (スマートcd)
  - `eza` (モダンls) / `bat` (ハイライト付きcat)
  - `ripgrep` (超高速grep) / `fd` (高速find)
  - `sd` (超高速正規表現置換/sed代替)
  - `ast-grep` (`sg`) (AST構造コード検索・リファクタ)
  - `jaq` / `jq` (超高速JSONプロセッサ)
  - `xh` (超高速HTTP/APIクライアント/curl代替)
  - `procs` (超高速プロセスビューア/ps代替)
  - `difftastic` (`difft`) (AST構文木差分ビューア)
  - `hexyl` (色分けバイナリ/Hexビューア)
  - `uutils-coreutils` (Rust製GNUコア: `head`, `tail`, `wc`, `sort`, `uniq`, `cut`, `tr`)
  - `lazygit` + `delta` (TUI Git + 美麗差分)
  - `hunk` (AIエージェント向けTUI diffレビュー)
  - `herdr` (AI TUIマルチプレクサ)
  - `bottom` (TUIモニタ) / `dust` (容量可視化) / `duf` (ディスク一覧)
  - `tealdeer` (高速tldr) / `just` (make代替) / `hyperfine` (ベンチマーク)
- **Editor / Formatter**:
  - `Helix` (モーダルエディタ) / `Cursor`
  - `Biome` (超高速 JS/TS Linter & Formatter)
  - `Taplo` (TOML LSP & Formatter)
- **Runtimes**:
  - `uv` (Python 環境管理)
  - `fnm` (Node.js バージョン管理)
  - `rustup` (Rust ツールチェーン)
