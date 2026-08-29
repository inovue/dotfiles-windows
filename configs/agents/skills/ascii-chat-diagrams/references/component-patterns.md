# ASCII Chat Diagram — Component Patterns

Box-drawing recipes, control notation, responsive layouts, and flow arrows for chat diagrams.

---

## 0. ASCII-First Recipes (Cursor chat — no Nerd Font)

Use these in Cursor chat. Validate with `python $ascii validate --mode sp --file diagram.txt`.

### SP header (W=32)
```text
┌──────────────────────────────┐
│ [#] App       { 2 }  [Menu]  │
├──────────────────────────────┤
```

### Controls (ASCII-safe)
| Control | Syntax | Example |
| :--- | :--- | :--- |
| Primary button | `[ Label ]` | `[ Save ]` |
| Ghost button | `( Label )` | `( Cancel )` |
| Text input | `< label... >` | `< Search... >` |
| Status chip | `{ text }` | `{ OK }` / `{ ERR }` |
| Flow arrow | `--->` | `Step A ---> Step B` |

Full chat-safe SP example: [examples/ascii-sp-dashboard.md](../examples/ascii-sp-dashboard.md)

---

## 1. Box-Drawing Charsets

### Light (Standard Single-Line)
- Corners: `┌` `┐` `└` `┘`
- Borders: `─` (Horizontal), `│` (Vertical)
- Junctions: `├` (Left-T), `┤` (Right-T), `┬` (Top-T), `┴` (Bottom-T), `┼` (Cross)

### Rounded (Modern / Soft UI)
- Corners: `╭` `╮` `╰` `╯`
- Borders: `─` `│`
- Junctions: `├` `┤` `┬` `┴` `┼`

### Heavy / Double-Line (Emphasized Containers & Modals)
- Double Corners: `╔` `╗` `╚` `╝`
- Double Borders: `═` `║`
- Double Junctions: `╠` `╣` `╦` `╩` `╬`

---

## 2. Component Semantics Grammar (Nerd Font — terminal only)

| UI Component | Syntax Pattern | Visual Example | Meaning |
| :--- | :--- | :--- | :--- |
| **Primary Action Button** | `[  <Action> ]` | `[  ログイン ]` | Main CTA (accent / highlighted) |
| **Secondary Button** | `( <Option> )` | `( キャンセル )` | Ghost / outlined alternative action |
| **Search / Text Input** | `<  <Label> >` | `<  ユーザー検索... >` | Single-line text input field |
| **Secure Password Input** | `<  <Label> >` | `<  パスワード入力 >` | Obfuscated / auth input container |
| **Checkbox Checked** | `[] <Label>` | `[] ログイン状態を保持` | Active / selected toggle option |
| **Checkbox Unchecked** | `[] <Label>` | `[] 通知を受け取る` | Inactive / unselected toggle option |
| **Radio Active** | `(•) <Label>` | `(•) 年額プラン ($99/yr)` | Mutually exclusive active choice |
| **Radio Inactive** | `( ) <Label>` | `( ) 月額プラン ($10/mo)` | Mutually exclusive inactive choice |
| **Media / Asset Tile** | `[~  <Label> ~]` | `[~  プレビュー画像 ~]` | Image, video, or canvas viewport |
| **Status Tag / Chip** | `{ <Icon> <Status> }`| `{  稼働中 }` | Badge, pill, or state indicator |
| **Key Shortcut Badge** | `[<Key>]` | `[Enter] 決定` `[Esc] 戻る` | Monospace keyboard hint |

---

## 3. Structural Layout Recipes

### Recipe A: Top Header / Navbar (PC Mode - W=80)
```text
┌──────────────────────────────────────────────────────────────────────────────┐
│  Financial Fantasy      <  銘柄・口座検索... >       {  2 }  (  山田太郎 ) │
├──────────────────────────────────────────────────────────────────────────────┤
```

### Recipe B: Tab Navigation Bar
```text
│ ┌─[  ダッシュボード ]─┐  ポートフォリオ    取引履歴    (  設定 )            │
├─┘                      └─────────────────────────────────────────────────────┤
```

### Recipe C: Multi-Column Flexbox (Sidebar + Main Panel - W=80)
```text
┌─[ ナビゲーション ]─────┬─[ 資産サマリー ]────────────────────────────────────┐
│  概要                │ 総資産額: ¥12,450,000                {  前日比 +2.4% } │
│  口座明細            ├──────────────────────────────────────────────────────┤
│  定期買付            │ [~  資産推移チャート (月次) ~]                      │
│  各種設定            │                                                      │
│                       │ [  今すぐ入金 ]     ( 出金申請 )     ( 明細CSV出力 ) │
└───────────────────────┴──────────────────────────────────────────────────────┘
```

### Recipe D: Form Container with Validation
```text
┌─[  アカウント新規登録 ]─────────────────────────────────────────────────────┐
│ 氏名 (必須):                                                                 │
│ <  山田 太郎 >                                                             │
│                                                                              │
│ メールアドレス:                                                              │
│ <  user@example.com >                                 {  利用可能 }       │
│                                                                              │
│ パスワード (8文字以上):                                                      │
│ <  •••••••••••••••• >                                 {  強度: 中 }       │
│                                                                              │
│ [] 利用規約およびプライバシーポリシーに同意する                             │
│                                                                              │
│ [  アカウントを作成 ]                          ( ログインへ戻る )           │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Recipe E: Modal Overlay Box
```text
┌─[  二要素認証 (2FA) 確認 ]──────────────────────────────────┐
│ 登録済みの認証アプリに送信された6桁の確認コードを入力してください:│
│                                                              │
│ <  123456 >                                                  │
│                                                              │
│ [  認証を完了 ]                      ( 別の方法でログイン ) │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. User Flow Diagram Notations (Flow Mode - W=120)

### Flow Grammar
- **Forward Action Transition**: `───  ( Action: Label ) ───>`
- **Return Action Transition**: `<───  ( Back: Label ) ─────`
- **Conditional Branching Node**: `├─ [Condition A] ─ ` / `└─ [Condition B] ─ `

### Flow Structure Example (Multi-Step Wizard)
```text
┌─[ Step 1: プラン選択 ]─────┐       ───  ( [  決定 ] ) ───>       ┌─[ Step 2: 決済情報入力 ]───┐
│ (•) プロプラン (¥1,980/月) │                                       │ <  カード番号 >           │
│ ( ) フリープラン (無料)    │                                       │ <  有効期限 > <  CVC >   │
│                            │       <───  ( ( 戻る ) ) ─────       │                            │
│ [  決済へ進む ]           │                                       │ [  支払いを確定する ]     │
└────────────────────────────┘                                       └────────────────────────────┘
```
