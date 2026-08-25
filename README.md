# dotfiles-windows

Nushell、Helix、Windows Terminal、および Rust/Go 製の高速モダン CLI ツールを中心とした Windows ネイティブ開発環境、ならびに **AI エージェント（Antigravity CLI, Cursor, Claude Code, Codex等）の超高速化・安定化** を実現する設定管理リポジトリです。

---

## 🌟 主な特徴・ハイライト

- ⚡ **AI エージェント超高速化・安定化 (SSOT)**:
  - 単一正本（`configs/agents/`）から Antigravity, Cursor, Claude Code, Codex へルール＆スキルを一括同期（`just sync-rules`）。
  - 🛡️ **決定論的サイバネティック・ガバナー (`agent_guard.py` / `hooks.json`)**: `PreToolUse` ライフサイクルフックにより、破壊的コマンド、遅い PowerShell Cmdlet、トークンを浪費する巨大ファイル読み込み、ワークスペース直接上書きを自動遮断。
  - ⚡ **LLMトークン消費 60-90% 削減プロキシ (`rtk`)**: Git/ビルド/テスト/ファイル閲覧等のコマンド出力をコンテキスト投入前に極限まで圧縮。
  - 遅い PowerShell Cmdlet をバイパスし、Rust/Go 製ネイティブ CLI（`rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft`, `rtk`）を直結。
  - 非対話ハング完全防止（`PAGER=cat`, `BAT_STYLE=plain`, `GIT_PAGER=cat`, `PYTHONUTF8=1` 等の環境変数永続化）。
  - Gated Graphify（`graphify-out/graph.json` 存在時のみ MCP/知識グラフを有効化し、不要な全リポジトリ走査を防止）。
  - 実ブラウザ自動化（`browser-agent` / Playwright）、ASTリファクタ（`modern-cli-expert`）、知識グラフ探索（`graphify-navigator`）の段階的開示スキル。
- 🐚 **モダンシェル＆ターミナル体験**:
  - Nushell を既定シェルとし、動的プロファイルフラグメントで Windows Terminal とシームレス統合。
  - Starship による美麗クロスシェルプロンプト、zoxide によるスマートディレクトリ移動。
  - `mm` コマンドによるターミナル内 Mermaid ダイアグラム表示（ASCII / Kroki+Chafa画像 / ブラウザ即時プレビュー）。
  - PowerShell 5.1 & 7 の非対話・UTF-8 最適化プロファイル。
- 🎨 **統一された美しさと操作性**:
  - `UDEV Gothic 35NF` (JetBrains Mono + BIZ UDゴシック + Nerd Fonts v3) 自動インストール・フォントレジストリ登録。
  - Catppuccin Mocha テーマ（Windows Terminal, Helix, Lazygit, Herdr）。
  - Helix（相対行番号、IME対策、Biome / Taplo / Rust LSP 連携）。
  - Herdr AI TUI マルチプレクサ + `herdr-sidebar`（VS Code風ファイルツリー・Git SCMサイドバー）。
  - Lazygit + Delta（構文ハイライト付き TUI Git クライアント）。
- 🔒 **セキュアな API キー管理**:
  - `just setup-keys` により、リポジトリにキーを一切保存せず Windows ユーザー環境変数にのみ対話型登録。

---

## 📂 ディレクトリ構成（責務の分離）

```text
dotfiles-windows/
├── AGENTS.md                       # 🧭 AIエージェント向けプロジェクトナビゲーション＆実行SSOT
├── CLAUDE.md                       # Claude Code 用プロジェクトガイド（AGENTS.md同期）
├── .cursorrules                    # Cursor 用プロジェクトルール（AGENTS.md同期）
├── justfile                        # Just タスクランナー定義（sync-rules, check-rules, deploy, test, setup-keys等）
├── install.ps1                     # 統合エントリポイント (全自動 or ステップ別実行, -UseSymlinks, -Force)
├── README.md                       # ユーザー向けドキュメント（本ファイル）
├── tests/
│   └── verify_tools.ps1            # 環境・モダンCLI・エージェント設定・ベンチマークの網羅的自動テスト
├── scripts/
│   ├── 01_winget_packages.ps1      # 1. winget によるツール・アプリ・ランタイム一括導入
│   ├── 02_install_fonts.ps1        # 2. UDEV Gothic NF (UDEV Gothic 35NF) 自動取得・登録
│   ├── setup_api_keys.ps1          # 🔑 AI Agent & Graphify 用 API キーの安全な対話型登録 (Windows ユーザー環境変数)
│   └── sync_agent_rules.ps1        # 🌟 AI Agent ルール＆スキルの高速一括同期 (正本 -> 全グローバル/ワークスペース)
└── configs/
    ├── agents/                     # 🌟 AIエージェント単一マスタールール (SSOT)
    │   ├── AGENTS.md               # グローバル共通ルール (CLI置換表, 非対話, UTF-8, ゼロハング)
    │   ├── hooks.json              # Antigravity 用 PreToolUse ライフサイクルフック設定
    │   ├── antigravity/            # Antigravity MCP テンプレ + always-on rules/workflows (graphify)
    │   │   ├── mcp_config.json
    │   │   ├── rules/graphify.md
    │   │   └── workflows/graphify.md
    │   ├── cursor/                 # Cursor always-on rules & hooks (graphify.mdc, hooks.json)
    │   │   ├── hooks.json
    │   │   └── rules/graphify.mdc
    │   └── skills/                 # 段階的開示スキル (Progressive Disclosure)
    │       ├── browser-agent/      # 実Chrome・Playwright・a11y・プロファイル自動化
    │       ├── graphify-navigator/ # Graphify×Antigravity ハイブリッド知識グラフナビゲータ
    │       ├── modern-cli-expert/  # ast-grep, sd, jaq, xh, procs, difftastic 高速レシピ
    │       └── rtk-expert/         # rtk トークン削減プロキシ超高速レシピ
    ├── powershell/                 # PowerShell 5.1 / 7 共通プロファイル (非対話高速化, エイリアス解除, UTF-8)
    │   └── Microsoft.PowerShell_profile.ps1
    ├── windows-terminal/           # Windows Terminal 設定 (UDEV Gothic 35NF, Catppuccin, Nushell既定, 動的プロファイル)
    │   └── settings.json
    ├── helix/                      # Helix 設定 (相対行番号, IME対策, Biome/Rust LSP連携)
    │   ├── config.toml
    │   └── languages.toml
    ├── nushell/                    # Nushell 設定 (Starship/zoxide連携, 高速モダンエイリアス, mm Mermaid連携)
    │   ├── config.nu
    │   └── env.nu
    ├── starship/                   # Starship 美麗クロスシェルプロンプト設定
    │   └── starship.toml
    ├── lazygit/                    # Lazygit TUI + Delta 構文ハイライト連携設定
    │   └── config.yml
    └── herdr/                      # Herdr 設定 (Nushell既定, Catppuccin, IME対策, herdr-sidebar連携)
        └── config.toml
```

---

## ⚡ クイックコマンド (`just`)

日常的な環境管理やルール同期は、タスクランナー `just` で1コマンド実行できます。

| コマンド | 内容 | 主な実行タイミング |
| :--- | :--- | :--- |
| `just audit` | 🌟 4フェーズ統合監査（テスト+SSOT同期+ナレッジグラフ健全性+ゴミファイル検知）を一括実行 | 調査・監査・状況確認の最初の一手 |
| `just test` | CLIツール、環境変数、SSOTルール、UTF-8、ベンチマークの網羅的自動テストを実行 | セットアップ後・定期動作確認 |
| `just clean` | 一時ファイル、古いバックアップ（`*.bak`）、ビルド・テストキャッシュを一括消去 | 編集完了後・コミット前 |
| `just sync-rules` | 🌟 正本（`configs/agents/`）から全エージェント・ワークスペースへルール/スキルを一括同期 | `configs/agents/` の編集後 |
| `just check-rules`| ルールが正本と同期されているか検証（差分チェック・CI用） | 変更前の確認やCI検証時 |
| `just deploy` | 全設定ファイル（Dotfiles + Rules）をユーザー環境にデプロイ | `configs/` 内の設定変更後 |
| `just checkpoint` | エージェントの編集前に安全な Git チェックポイントブランチを作成 | 大規模・破壊的リファクタリング前 |
| `just rollback` | 直前のチェックポイントブランチへ安全に即時ロールバック | 破壊的編集の取り消し時 |
| `just graph <q>`| 🧠 高速知識グラフ検索（`just graph "deploy"` 等） | 構造探索・シンボル影響調査 |
| `just hubs` | コードベース全体の重要アーキテクチャハブ・Godノードを一覧 | 全体構造の俯瞰 |
| `just neighbors <l>`| 特定ハブ・ファイルの近傍コンポーネントと関係性を展開 | ハブ展開・変更波及範囲確認 |
| `just path <a> <b>` | 2つのコンポーネント間の最短呼び出し/依存パスを探索 | 依存関係・リファクタ影響調査 |
| `just update-graph`| 高速 AST 解析によりナレッジグラフ（`graphify-out/`）を更新 | 編集バッチ完了時 |
| `just install` | 環境構築（パッケージ、フォント、ランタイム、設定）を一括実行 | 新規マシン構築時 |
| `just setup-keys` | 🔑 AI Agent & Graphify 用 API キーを Windows ユーザー環境変数に対話型登録 | APIキー初回設定・更新時 |

---

## 🚀 使い方 / インストール手順

PowerShell を **管理者権限** で開き、本リポジトリのディレクトリで実行します。

### 1. 一括セットアップ（推奨）

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

### 2. ステップごとの個別実行

必要なステップのみを個別に実行することも可能です。

| コマンド | 実行内容 |
| :--- | :--- |
| `.\install.ps1 -Step 1` | `winget` によるパッケージの一括インストール (Terminal, CLI, Editors, Runtimes, Apps) |
| `.\install.ps1 -Step 2` | `UDEV Gothic NF` (35NF) フォントの自動ダウンロード・Windows 登録 (`-Force` で再取得可) |
| `.\install.ps1 -Step 3` | ランタイム初期化 (fnm/Node, uv/Python + Playwright, Rustup/jaq, Graphify, hunkdiff, herdr-sidebar, Cursor Agent CLI, 安全環境変数, `~/.local/bin` シム) |
| `.\install.ps1 -Step 4` | 設定ファイル（Dotfiles: Windows Terminal, Helix, Nushell, Profiles）および AI Agent ルールの一括配備 (`just deploy`) |
| `just sync-rules` | AI Agent ルール＆スキルのみを高速一括同期 (`.\scripts\sync_agent_rules.ps1`) |
| `just setup-keys` | AI Agent & Graphify 用 API キーの安全な対話型登録 (`.\scripts\setup_api_keys.ps1`) |
| `just audit` | 🌟 4フェーズ統合監査（テスト+SSOT同期+グラフ健全性+ゴミ検知）の実行 (`.\scripts\audit_workspace.ps1`) |
| `just clean` | 一時ファイル・古いバックアップ（`*.bak`）・キャッシュの一括消去 (`.\scripts\audit_workspace.ps1 -Clean`) |
| `just test` | 環境全体の整合性・ツール動作確認・ベンチマークテスト (`.\tests\verify_tools.ps1`) |

---

## 🤖 AI Agent 超高速化・安定化アーキテクチャ (SSOT)

本環境では、AI エージェント（Antigravity, Cursor Agent, Claude Code, Codex）が Windows 上で動作する際の遅延・ハング・文字化けを徹底的に排除しています。

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AI Agent Ultra-Fast Execution Protocol                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. 単一正本 (SSOT): configs/agents/ -> just sync-rules で全エージェントへ配備  │
│ 2. ネイティブCLI優先: rg, fd, sd, ast-grep, jaq, xh, procs, difftastic       │
│ 3. 非対話・ゼロハング: PAGER=cat, BAT_STYLE=plain, -NoProfile, UTF-8 永続化   │
│ 4. Gated Graphify: graphify-out/graph.json 存在時のみ MCP/知識グラフを起動   │
│ 5. 段階的開示スキル: browser-agent, modern-cli-expert, graphify-navigator   │
│ 6. ガバナー抑止: agent_guard.py により危険コマンド・低速Cmdletを物理遮断     │
└─────────────────────────────────────────────────────────────────────────────┘
```

1. **二重管理ゼロの SSOT ルール**:
   - `configs/agents/` を唯一のマスターとし、`just sync-rules` で各エージェントのグローバルパス（`~/.gemini/config/`, `~/.claude/`, `%APPDATA%/Cursor/User/` 等）へ自動配備。
2. **ネイティブ高速 CLI ツールの優先**:
   - 重い PowerShell Cmdlet（`Get-Content`, `Select-String`, `ConvertFrom-Json`）をバイパスし、Rust/Go 製バイナリを直接実行。
3. **非対話ハング・文字化けの完全防止**:
   - `PAGER=cat`, `BAT_PAGER=""`, `BAT_STYLE=plain`, `GIT_PAGER=cat`, `DELTA_PAGER=cat`, `PYTHONUTF8=1` をユーザー環境変数に永続化し、ページャー待ちや ANSI エスケープ破綻を封殺。
4. **Gated Graphify アーキテクチャ**:
   - 知識グラフツール（`graphify` / `graphify-mcp`）は、対象プロジェクトに `graphify-out/graph.json` が存在する場合のみ利用（通常プロジェクトでの無駄な全走査やトークン消費を防止）。
5. **段階的開示スキル (Progressive Disclosure)**:
   - `browser-agent`: 実 Google Chrome + Playwright によるログインセッション維持・動的SPAスクレイピング。
   - `modern-cli-expert`: `ast-grep`, `sd`, `jaq`, `xh`, `procs`, `difftastic`, `hyperfine` の実践的活用レシピ。
   - `graphify-navigator`: Graphify × 高速 CLI のハイブリッドコードベース探索。
   - `rtk-expert`: `rtk` による Git・テスト・ビルド・ファイル閲覧の 60-90% トークン削減プロキシ・スマート要約・失敗ログ復旧レシピ。
6. **決定論的サイバネティック・ガバナー (`agent_guard.py`)**:
   - `PreToolUse` ライフサイクルフックにより、破壊的コマンド（`format`, `diskpart`, `rmdir /s C:\`, `git push --force`）、低速 PowerShell パイプライン（`Select-String`, `Get-ChildItem -Recurse`）、120行以上の未スライスファイル読み込み、ワークスペースソースファイルの直接上書きを自動遮断。

---

## 🛠 主な同梱ツール一覧

### 🤖 Autonomous AI Agents & CLIs
- **Google Antigravity CLI** (`agy`) - 高性能コーディングエージェント CLI
- **Cursor Agent CLI** (`agent` / `cursor-agent`) - Cursor バックエンドエージェント CLI
- **Claude Code** (`claude`) - Anthropic Agentic CLI

### 🐚 Shell & Terminal
- **Windows Terminal** - Catppuccin Mocha テーマ、UDEV Gothic 35NF、動的 Nushell プロファイル統合
- **Nushell** (`nu`) - モダン構造化データシェル（Starship, zoxide, `mm` Mermaid レンダラー連携）
- **PowerShell 7** (`pwsh`) / **Windows PowerShell 5.1** - UTF-8 / 非対話高速化プロファイル

### 🔤 Font
- **UDEV Gothic 35NF** - JetBrains Mono + BIZ UDゴシック + Nerd Fonts v3（半角3:全角5比率、プログラミング＆日本語最適化）

### ⚡ CLI Utilities (Rust / Go / Native)
- **`ripgrep` (`rg`)** - 超高速テキスト・正規表現検索
- **`fd`** - 高速ファイル・ディレクトリ検索
- **`sd`** - 超高速正規表現置換（sed 代替）
- **`ast-grep` (`sg`)** - AST 構文木認識コード検索・リファクタリング
- **`bat`** - シンタックスハイライト付きファイルビューア（非対話プレーンモード対応）
- **`eza`** - モダン ls / ツリー表示
- **`jaq` / `jq`** - 超高速 JSON ストリームプロセッサ（Rust `jaq` 優先）
- **`rtk`** - LLM トークン消費 60-90% 削減 CLI プロキシ（Git/テスト/閲覧のノイズ除去＆自動要約）
- **`xh`** - 超高速 HTTP/API クライアント（curl 代替、JSON 自動処理）
- **`procs`** - 高速プロセスビューア / ポート番号検索（ps 代替）
- **`difftastic` (`difft`)** - AST 構文木構造差分ビューア
- **`hexyl`** - 色分けバイナリ / 16進数ビューア
- **`uutils-coreutils` / `diffutils`** - Rust 製 GNU コアユーティリティ（`head`, `tail`, `wc`, `sort`, `uniq`, `cut`, `tr` 等）
- **`fzf`** - 汎用ファジーファインダー
- **`glow`** - ターミナル Markdown リッチレンダラー
- **`chafa`** - 超高速ターミナル画像 / Sixel レンダラー
- **`graphify` / `graphify-mcp`** - 知識グラフ生成 CLI / MCP サーバー（Gated Always-on）
- **`Starship`** - 超高速クロスシェルプロンプト
- **`zoxide`** - スマートディレクトリジャンプ（`z` コマンド）
- **`just`** - モダンコマンドランナー（make 代替）
- **`hyperfine`** - 高精度 CLI ベンチマーク測定
- **`tealdeer` (`tldr`)** - 高速コマンドチートシート
- **`bottom` (`btm`)** - TUI システムモニタ
- **`dust` / `duf`** - ディレクトリ容量可視化 / ディスク一覧

### 🖥️ TUI Multiplexer & Git
- **`herdr`** - AI 向け TUI マルチプレクサ（Nushell 既定、Catppuccin）
- **`herdr-sidebar`** - VS Code 風ファイルツリー・Git SCM サイドバープラグイン
- **`lazygit` + `delta`** - TUI Git クライアント + 美麗シンタックスハイライト差分
- **`hunk` (`hunkdiff`)** - AI エージェント向け TUI diff レビュー

### 📝 Editors & DevTools
- **`Helix` (`hx`)** - モダンモーダルエディタ（Tree-sitter, LSP 内蔵, 相対行番号, IME対策）
- **`Cursor`** - AI 駆動コードエディタ
- **`Git` / `GitHub CLI` (`gh`)**
- **`Bruno`** - 軽量・オフライン API クライアント
- **`Fly.io CLI` (`flyctl`)**

### 📦 Runtimes & Formatters
- **`uv`** - 超高速 Python パッケージ/ランタイムマネージャー
- **`fnm`** - Rust 製 高速 Node.js バージョンマネージャー (Node.js LTS)
- **`pnpm` / `Bun`** - 高速 JS/TS パッケージマネージャー & ランタイム
- **`Rustup` / `Cargo`** - Rust ツールチェーン
- **`Biome`** - 超高速 JS/TS リンター & フォーマッター
- **`Taplo`** - TOML LSP & フォーマッター
- **`Playwright`** - ブラウザ自動化ライブラリ（`browser-agent` スキル用）

### 🧰 Desktop Utilities & Apps
- **`FFmpeg` / `libvips`** - 動画・画像高速処理ライブラリ
- **`7-Zip` / `PowerToys` / `Bitwarden` / `QuickLook` / `Everything`**
- **`Discord` / `Slack` / `Spotify` / `CapCut` / `Steam`**
