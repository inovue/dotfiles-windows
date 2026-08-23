# dotfiles-windows

Nushell、Helix、Windows Terminal、および Rust/Go 製の高速モダン CLI ツールを中心とした Windows ネイティブ開発環境のセットアップ＆設定管理リポジトリです。

---

## 📂 ディレクトリ構成（責務の分離）

```
dotfiles-windows/
├── install.ps1                     # 統合エントリポイント (全自動 or ステップ別実行)
├── README.md                       # 本ドキュメント
├── scripts/
│   ├── 01_winget_packages.ps1      # 1. winget によるツール・アプリ一括導入
│   ├── 02_install_fonts.ps1        # 2. HackGen_NF (日本語 + Nerd Fonts) 自動取得・登録
│   ├── 03_setup_runtimes.ps1       # 3. fnm(Node) / uv(Python) / Rust の初期化
│   └── 04_setup_configs.ps1        # 4. Windows Terminal/Helix/Nushell/Starship 設定配備
└── configs/
    ├── windows-terminal/           # Windows Terminal 設定 (HackGen Console NF, Catppuccin, Nushell既定)
    │   └── settings.json
    ├── helix/                      # Helix 設定 (相対行番号, IME対策, Biome/Rust LSP連携)
    │   ├── config.toml
    │   └── languages.toml
    ├── nushell/                    # Nushell 設定 (Starship/zoxide連携, 高速モダンエイリアス)
    │   ├── config.nu
    │   └── env.nu
    ├── starship/starship.toml      # Starship 美麗プロンプト設定
    └── lazygit/config.yml          # Lazygit + Delta 連携設定
```

---

## 🚀 使い方

PowerShell を **管理者権限** で開き、本ディレクトリに移動して実行します。

### 一括セットアップ（推奨）

```powershell
.\install.ps1 -All
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
| `.\install.ps1 -Step 2` | `HackGen_NF` フォントの自動ダウンロード・登録 |
| `.\install.ps1 -Step 3` | `fnm` (Node LTS) / `uv` (Python) / `Rust` / `tldr` の初期化 |
| `.\install.ps1 -Step 4` | 設定ファイル（Dotfiles）のユーザーディレクトリへの配備 |

---

## 🛠 主な同梱ツール一覧

- **Shell / Terminal**: Nushell, Windows Terminal
- **Font**: HackGen Console NF (Hack + 源柔ゴシック + Nerd Fonts)
- **CLI Utilities (Rust/Go)**:
  - `Starship` (プロンプト) / `zoxide` (スマートcd)
  - `eza` (モダンls) / `bat` (ハイライト付きcat)
  - `ripgrep` (高速grep) / `fd` (高速find)
  - `lazygit` + `delta` (TUI Git + 美麗差分)
  - `bottom` (TUIモニタ) / `dust` (容量可視化) / `duf` (ディスク一覧)
  - `tealdeer` (高速tldr) / `just` (make代替)
- **Editor / Formatter**:
  - `Helix` (モーダルエディタ) / `Cursor`
  - `Biome` (超高速 JS/TS Linter & Formatter)
  - `Taplo` (TOML LSP & Formatter)
- **Runtimes**:
  - `uv` (Python 環境管理)
  - `fnm` (Node.js バージョン管理)
  - `rustup` (Rust ツールチェーン)
