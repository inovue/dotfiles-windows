# dotfiles-windows

Nushell、Helix、Windows Terminal、および Rust/Go 製の高速モダン CLI ツールを中心とした Windows ネイティブ開発環境、ならびに **Cursor を Windows 上で超高速化・安定化する** 設定管理リポジトリです。

---

## 🌟 主な特徴・ハイライト

- ⚡ **AI エージェント超高速化・安定化 (SSOT)**:
  - 単一正本（`configs/agents/`）から Cursor へルール＆スキルを同期（`just sync-rules`）。配備先は `~/.cursor` と `%APPDATA%/Cursor/User` のみ。
  - ⚡ **LLMトークン消費 60-90% 削減プロキシ (`rtk`)**: 公式 `rtk init -g --agent cursor --hook-only` が `~/.cursor/hooks.json` に `rtk hook cursor` を入れ、Shell を透過 rewrite する（fail-open、deny しない）。
  - 遅い PowerShell Cmdlet をバイパスし、Rust/Go 製ネイティブ CLI（`rg`, `fd`, `sd`, `ast-grep`, `jaq`, `xh`, `procs`, `difft`, `rtk`）を直結。一括行探索（Batch Line Discovery）やマルチターゲット検索のバッチ化を徹底。
  - 非対話ハング完全防止（`PAGER=cat`, `BAT_STYLE=plain`, `GIT_PAGER=cat`, `PYTHONUTF8=1` 等の環境変数永続化）。
  - 実ブラウザ自動化（`browser-agent` / Playwright）、チャット内 ASCII 図（`ascii-chat-diagrams`）、ASTリファクタ（`modern-cli-expert`）の段階的開示スキル。
- 🐚 **モダンシェル＆ターミナル体験**:
  - Nushell を既定シェルとし、動的プロファイルフラグメントで Windows Terminal とシームレス統合。
  - Starship による美麗クロスシェルプロンプト、zoxide によるスマートディレクトリ移動。
  - `mm` コマンドによるターミナル内 Mermaid ダイアグラム表示（ASCII / Kroki+Chafa画像 / ブラウザ即時プレビュー）。
  - PowerShell 5.1 & 7 の非対話・UTF-8 最適化プロファイル。
- 🎨 **統一された美しさと操作性**:
  - `UDEV Gothic NF` (JetBrains Mono + BIZ UDゴシック + Nerd Fonts v3) 自動インストール・フォントレジストリ登録。
  - Catppuccin Mocha テーマ（Windows Terminal, Helix, Lazygit, Herdr）。
  - Helix（相対行番号、IME対策、Biome / Taplo / Rust LSP 連携）。
  - Herdr AI TUI マルチプレクサ + `herdr-sidebar`（VS Code風ファイルツリー・Git SCMサイドバー）。
  - Lazygit + Delta（構文ハイライト付き TUI Git クライアント）。
- 🔒 **セキュアな API キー管理**:
  - `just setup-keys` / `just setup-fal` により、リポジトリにキーを一切保存せず Windows ユーザー環境変数（`OPENAI_API_KEY`, `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `FAL_KEY` 等）にのみ対話型登録。

---

## 📂 ディレクトリ構成（責務の分離）

```text
dotfiles-windows/
├── AGENTS.md                       # 🧭 AIエージェント向けプロジェクトガイド（唯一の常時ロード原本）
├── justfile                        # Just タスクランナー定義（sync-rules, check-rules, deploy, test, setup-keys等）
├── install.ps1                     # 統合エントリポイント (全自動 or ステップ別実行, -UseSymlinks, -Force)
├── README.md                       # ユーザー向けドキュメント（本ファイル）
├── tests/
│   ├── verify_tools.ps1            # 環境・モダンCLI・エージェント設定・ベンチマークの網羅的自動テスト
│   └── verify_security.ps1         # 🛡️ セキュリティ回帰テスト（URL検証、SHA256ピン、XSS、パストラバーサル）
├── scripts/
│   ├── 01_winget_packages.ps1      # 1. winget によるツール・アプリ・ランタイム一括導入
│   ├── 02_install_fonts.ps1        # 2. UDEV Gothic NF (等幅/等倍) 自動取得・登録
│   ├── 03_setup_runtimes.ps1       # 3. fnm, uv, rustup, jaq, rtk 等のランタイム・CLIセットアップ
│   ├── 04_setup_configs.ps1        # 4. Dotfiles（Terminal, Helix, Nushell, Profiles）の配備
│   ├── Assert-PinnedHash.ps1       # 🔒 バイナリダウンロードの SHA256 ピン & TOFU 整合性検証
│   ├── audit_workspace.ps1         # 🌟 統合監査・クリーンアップスクリプト
│   ├── report_session_log.py       # 📊 セッションログのトークン節約・deny率・Thrash発生状況の集計レポート
│   ├── setup_api_keys.ps1          # 🔑 AI Agent 用 API キーの安全な対話型登録 (Windows ユーザー環境変数)
│   └── sync_agent_rules.ps1        # 🌟 Cursor ルール＆スキルの高速同期 (正本 -> ~/.cursor と %APPDATA%/Cursor/User)
└── configs/
    ├── agents/                     # 🌟 Cursor 単一マスタールール (SSOT)
    │   ├── GLOBAL_RULES.md         # グローバル共通ルール正本 (CLI置換表, 非対話, UTF-8, ゼロハング)
    │   ├── cursor/                 # Cursor MCP テンプレ
    │   │   └── mcp_config.json     # Cursor MCP テンプレ（サーバーなし）
    │   └── skills/                 # 段階的開示スキル (Progressive Disclosure)
    │       ├── browser-agent/      # 実Chrome・Playwright・persistent profile・dev/SSO capture
    │       ├── modern-cli-expert/  # ast-grep, sd, jaq, xh, procs, difftastic 高速レシピ
    │       └── ascii-chat-diagrams/  # チャット内 ASCII/Unicode 図（wireframe, chart, table, flow）
    ├── powershell/                 # PowerShell 5.1 / 7 共通プロファイル (非対話高速化, エイリアス解除, UTF-8)
    │   └── Microsoft.PowerShell_profile.ps1
    ├── windows-terminal/           # Windows Terminal 設定 (UDEV Gothic NF, Catppuccin, Nushell既定, 動的プロファイル)
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
    ├── rtk/                        # rtk 設定 (トークン削減・除外設定)
    │   └── config.toml
    └── herdr/                      # Herdr 設定 (Nushell既定, Catppuccin, IME対策, herdr-sidebar連携)
        └── config.toml
```

---

## ⚡ クイックコマンド (`just`)

日常的な環境管理やルール同期は、タスクランナー `just` で1コマンド実行できます。

| コマンド | 内容 | 主な実行タイミング |
| :--- | :--- | :--- |
| `just audit` | 🌟 3フェーズ統合監査（テスト+SSOT同期+ゴミファイル検知）を一括実行 | 調査・監査・状況確認の最初の一手 |
| `just test` | CLIツール、環境変数、SSOTルール、UTF-8、ベンチマークの網羅的自動テストを実行 | セットアップ後・定期動作確認 |
| `just clean` | 一時ファイル、古いバックアップ（`*.bak`）、ビルド・テストキャッシュを一括消去 | 編集完了後・コミット前 |
| `just sync-rules` | 🌟 正本（`configs/agents/`）から Cursor（`~/.cursor`, `%APPDATA%/Cursor/User`）へルール/スキルを同期 | `configs/agents/` の編集後 |
| `just check-rules`| ルールが正本と同期されているか検証（差分チェック・CI用） | 変更前の確認やCI検証時 |
| `just deploy` | 全設定ファイル（Dotfiles + Rules）をユーザー環境にデプロイ | `configs/` 内の設定変更後 |
| `just checkpoint` | エージェントの編集前に安全な Git チェックポイントブランチを作成 | 大規模・破壊的リファクタリング前 |
| `just rollback` | 直前のチェックポイントブランチへ安全に即時ロールバック | 破壊的編集の取り消し時 |
| `just session-report` | 📊 セッションログの deny 率、Thrash、累積スライス (crawl)、短周期待ち誘導 (poll_guide) を集計 | エージェント動作品質・トークン効率検証 |
| `just rtk-gain` | 📊 rtk のトークン削減統計ダッシュボードを表示 | トークン節約効果の確認 |
| `just rtk-history` | 直近のコマンド実行履歴とトークン削減率の内訳を表示 | 直近の節約履歴確認 |
| `just rtk-discover`| 削減可能な見落としコマンドを履歴から自動検出 | エージェント最適化の確認 |
| `just update-rtk` | rtk を最新リリースに更新し、ルール再同期とテストを実行 | rtk アップデート時 |
| `just install` | 環境構築（パッケージ、フォント、ランタイム、設定）を一括実行 | 新規マシン構築時 |
| `just setup-keys` | 🔑 AI Agent 用 API キーを Windows ユーザー環境変数に対話型登録 | APIキー初回設定・更新時 |
| `just setup-fal` | 🎨 fal.ai API キー（`FAL_KEY`）を Windows ユーザー環境変数に対話型登録 | 画像生成機能利用時 |

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
| `.\install.ps1 -Step 2` | `UDEV Gothic NF` フォントの自動ダウンロード・Windows 登録 (`-Force` で再取得可) |
| `.\install.ps1 -Step 3` | ランタイム初期化 (fnm/Node, uv/Python + Playwright, Rustup/jaq, hunkdiff, herdr-sidebar, Cursor Agent CLI, 安全環境変数, `~/.local/bin` シム) |
| `.\install.ps1 -Step 4` | 設定ファイル（Dotfiles: Windows Terminal, Helix, Nushell, Profiles）および AI Agent ルールの一括配備 (`just deploy`) |
| `just sync-rules` | Cursor ルール＆スキルのみを高速同期 (`.\scripts\sync_agent_rules.ps1`) |
| `just setup-keys` | AI Agent 用 API キーの安全な対話型登録 (`.\scripts\setup_api_keys.ps1`) |
| `just audit` | 🌟 3フェーズ統合監査（テスト+SSOT同期+ゴミ検知）の実行 (`.\scripts\audit_workspace.ps1`) |
| `just clean` | 一時ファイル・古いバックアップ（`*.bak`）・キャッシュの一括消去 (`.\scripts\audit_workspace.ps1 -Clean`) |
| `just test` | 環境全体の整合性・ツール動作確認・セキュリティ回帰 (`.\tests\verify_tools.ps1` + `verify_security.ps1`) |

---

## 🤖 AI Agent 超高速化・安定化アーキテクチャ (SSOT)

本環境では、**Cursor** が Windows 上で動作する際の遅延・ハング・文字化けを徹底的に排除しています。

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AI Agent Ultra-Fast Execution Protocol                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. 単一正本 (SSOT): configs/agents/ -> just sync-rules で Cursor へ配備        │
│ 2. ネイティブCLI優先: rg, fd, sd, ast-grep, jaq, xh, procs, difftastic       │
│ 3. 非対話・ゼロハング: PAGER=cat, BAT_STYLE=plain, -NoProfile, UTF-8 永続化   │
│ 4. 段階的開示スキル: browser-agent, ascii-chat-diagrams, modern-cli-expert │
│ 5. rtk: 公式 Cursor hook が Shell を透過 rewrite（deny しない）              │
└─────────────────────────────────────────────────────────────────────────────┘
```

1. **二重管理ゼロの SSOT ルール & 高速編集プロトコル**:
   - `configs/agents/` を唯一のマスターとし、`just sync-rules` で Cursor のグローバルパス（`~/.cursor`, `%APPDATA%/Cursor/User`）へ自動配備。
   - トークン浪費を徹底排除する一括行探索（Batch Line Discovery: `rg -n -e 'a' -e 'b'` 1回で全対象を特定）と行番号指定ツールの Bottom-Up 編集プロトコルを厳格適用。
2. **ネイティブ高速 CLI ツールの優先**:
   - 重い PowerShell Cmdlet（`Get-Content`, `Select-String`, `ConvertFrom-Json`）をバイパスし、Rust/Go 製バイナリを直接実行。
3. **非対話ハング・文字化けの完全防止**:
   - `PAGER=cat`, `BAT_PAGER=""`, `BAT_STYLE=plain`, `GIT_PAGER=cat`, `DELTA_PAGER=cat`, `PYTHONUTF8=1` をユーザー環境変数に永続化し、ページャー待ちや ANSI エスケープ破綻を封殺。
4. **段階的開示スキル (Progressive Disclosure)**:
   - `browser-agent`: 実 Google Chrome + Playwright。localhost capture（`temp`）と、`setup_profile` 後のダッシュボード確認（`work` / screenshot 必須）。無人 SSO 自動化は非対象。
   - `ascii-chat-diagrams`: チャット内 ASCII/Unicode 図（wireframe、比較表、棒グラフ、フロー）。`just sync-rules` で `~/.cursor/skills/ascii-chat-diagrams/` に配備。**Cursor のみ**（Claude Code 非対象）。
   - `modern-cli-expert`: `ast-grep`, `sd`, `jaq`, `xh`, `procs`, `difftastic`, `hyperfine` の実践的活用レシピ。
5. **公式 rtk Cursor hook**:
   - `rtk init -g --agent cursor --hook-only --auto-patch` が `~/.cursor/hooks.json` に `rtk hook cursor` を入れる。fail-open。このリポジトリは hooks.json を上書きしない。

### browser-agent クイックスタート

dev サーバ capture と、人手 login 済み profile でのダッシュボード確認用スキル。SSOT: `configs/agents/skills/browser-agent/` → `just sync-rules` で `~/.cursor/skills/browser-agent/` に配備。

```powershell
# 初回: プロファイル作成 & 人手ログイン（SSO ダッシュボード用）
pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\setup_profile.ps1" -ProfileName work

# ページ確認（auth_state はヒントのみ — screenshot で目視確認）
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" inspect --url "https://example.com" --profile work

# dev サーバ screenshot / scroll video（--profile temp が既定）
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" screenshot --url "localhost:5173" --profile temp --headless --output .\cap.png --full-page
python "$env:USERPROFILE\.cursor\skills\browser-agent\scripts\browser_runner.py" record --url "localhost:5173" --profile temp --output .\scroll.webm

# Windows: act は必ず --actions-file を使う（JSON 直書き不可）

# 任意: SSO 実機 smoke（work profile + ネットワーク必要）
just test-browser-sso-run
```

詳細レシピはスキル `browser-agent`（`SKILL.md`）を参照。自動テスト: `just test`（108 件 smoke + SSO manual は skip）。

### ascii-chat-diagrams クイックスタート

対話中の UI/フロー/数値の認識合わせ用。SSOT: `configs/agents/skills/ascii-chat-diagrams/` → `just sync-rules` で `~/.cursor/skills/ascii-chat-diagrams/` に配備（**Windows + Cursor のみ**）。

```powershell
# 配備（install Step 4 / just deploy / just sync-rules のいずれかで実行済みなら不要）
just sync-rules

$ascii = "$env:USERPROFILE\.cursor\skills\ascii-chat-diagrams\scripts\ascii_diagram_helper.py"

# ラフ下書き → 幅固定（UTF-8 no BOM で draft.txt に保存）
python $ascii autofit --mode pc --file .\draft.txt

# チャート / 比較表（generator 直呼び）
python $ascii barchart --labels "A,B,C" --values "40,65,25" --width 60
python $ascii table --headers "Plan,Price" --rows "Free,0|Pro,980" --width 56
python $ascii sparkline --values "1,3,2,5,4,6" --mode inline

# 検証（CJK / 多列レイアウト時）
python $ascii validate --mode pc --file .\diagram.txt
```

Cursor チャットでは `@ascii-chat-diagrams` または「ASCII で図示して」。チャット向け模範: スキル内 `examples/ascii-*.md`（Nerd Font 不要）。自動テスト: `just test` 内の `verify_ascii_chat_diagrams.ps1`（20 件）。

---

## 🛠 主な同梱ツール一覧

### 🤖 Autonomous AI Agents & CLIs
- **Cursor Agent CLI** (`agent` / `cursor-agent`) - Cursor バックエンドエージェント CLI

### 🐚 Shell & Terminal
- **Windows Terminal** - Catppuccin Mocha テーマ、UDEV Gothic NF、動的 Nushell プロファイル統合
- **Nushell** (`nu`) - モダン構造化データシェル（Starship, zoxide, `mm` Mermaid レンダラー連携）
- **PowerShell 7** (`pwsh`) / **Windows PowerShell 5.1** - UTF-8 / 非対話高速化プロファイル

### 🔤 Font
- **UDEV Gothic NF** - JetBrains Mono + BIZ UDゴシック + Nerd Fonts v3（半角1:全角2 等幅比率、プログラミング＆日本語最適化）

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
- **`Python 3`** - `ascii_diagram_helper.py` 実行用（`uv` / winget 経由。追加パッケージ不要）

### 🧰 Desktop Utilities & Apps
- **`FFmpeg` / `libvips`** - 動画・画像高速処理ライブラリ
- **`7-Zip` / `PowerToys` / `Bitwarden` / `QuickLook` / `Everything`**
- **`Discord` / `Slack` / `Spotify` / `CapCut` / `Steam`**
