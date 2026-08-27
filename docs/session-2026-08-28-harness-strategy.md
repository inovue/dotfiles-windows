# Session Report: Agent Harness Strategy & Cursor Baseline (2026-08-28)

このドキュメントは 2026-08-28 セッションで議論した方針・分析・未実装提案・実装済み変更を漏れなく記録する。

---

## 1. セッションの目的と結論

| テーマ | 結論 |
| :--- | :--- |
| ガードレール肥大化 | **意図的二重壁 + 現場パッチ積層 (v2→v4.7)** が主因。deny 2.9%・デッドロックなしのため **機能としては適切寄り**。債務は monofile・soft/hard 政策エコー・テストミラー。 |
| 次の構造改善 | **ACI アダプタ分離** + **soft 側ゲート詳細の hooks 委譲**（`GUARD_POLICY.md` SSOT 化） |
| Cursor × Windows 最適化 | シェルは **`pwsh -NoProfile -NonInteractive` 維持**。速度は nu より **フック二重起動削減・マルチハーネス同期削除** が効く。 |
| 今回実装 | **セットアップ時に Cursor/Windows 基盤を固定**し、エージェントは「前提設定済み」として開始する **Harness Baseline** |

---

## 2. ガードレール肥大化の分析

### 2.1 レイヤ構造

```text
[SOFT] prompt / rules                    [HARD] hooks / deterministic
GLOBAL_RULES.md + graphify.mdc           agent_guard.py v4.7 (~66KB / 1613L)
+ on-demand skills                       hard-deny + one-strike gates
        │                                        ▲
        │ mirrors / sync-rules                   │ PreToolUse / stop
        v                                        │
skills (navigator, builder, rtk)         hooks.json → python scripts/agent_guard.py
```

### 2.2 肥大の5要因

1. **マルチハーネス ACI** — Cursor / Claude / Antigravity の JSON・待ちパラメータ・ツール名差分
2. **Graph walls + fallback** — graph-gate, edit-gate, query-log 180s, MCP unwrap
3. **トークン壁** — read cap 300, crawl, rtk, read budget 8 files
4. **状態レース修正** — atomic save, merge, conv-id fallback (v4.1〜4.3)
5. **PS5.1 vs pwsh** — `powershell.exe` + `&&` 誤検知修正 (v4.6)

### 2.3 コストシグナル（セッション時点）

| 指標 | 値 |
| :--- | :--- |
| `agent_guard.py` | ~66KB / 1613 行、グラフ hub degree 61 |
| `verify_agent_guard.ps1` | ~57KB（本体と同規模の回帰ミラー） |
| Session deny 率 | 2.9% (29/1017) |
| thrash | 0% |
| crawl ヒット | 11 |

### 2.4 適切性の判定

- **適切**: one-strike + fail-open、破壊コマンドのみ hard-deny、実測バグへのパッチ
- **債務**: 1613 行 monofile、GLOBAL_RULES がゲート一覧を再記述、graph contact 3 経路、テスト並走肥大

---

## 3. 未実装: 構造改善ロードマップ

### 3.1 ACI アダプタ分離

`agent_guard.py` の責務を分割する提案（**今回未着手**）。

```text
scripts/agent_guard/
  policy.py          # inspect_* — harness 引数なし
  state.py           # TTL / merge / strikes
  discovery.py       # repo root / graph contact
  adapters/
    cursor.py        # emit / parse / block_until_ms floor
    claude.py        # permissionDecision + exit 2
    antigravity.py   # WaitMs 10000 / stop continue
```

`inspect_run_command` から `harness` 引数を除去し、`adapter.finite_wait_floor_ms()` 経由にする。

**移行フェーズ**: types → adapters に emit/parse 移動 → policy から harness 除去 → shim 化。

### 3.2 Soft 側ゲート詳細の一本化

| 層 | 役割 |
| :--- | :--- |
| `configs/agents/GUARD_POLICY.md` (新規予定) | ゲート表・tunables・recovery hint の唯一の人間可読 SSOT |
| `GLOBAL_RULES.md` | 文化・手順のみ。「Guarantees live in hooks → GUARD_POLICY」 |
| `graphify.mdc` | 「Hooks are walls → GUARD_POLICY §graph-gate」1 行 |
| `agent_guard/policy.py` | 機械実装 |

`gen_guard_policy.py` で doc ↔ 定数の drift 防止も検討。

### 3.3 Cursor-only 同期・最適化（未実装）

- `sync-rules -Profile Cursor` で Antigravity/Claude ターゲット削除
- hooks matcher を Cursor ネイティブ名のみに絞る
- `rtk hook cursor` を guard 内統合（Shell あたりプロセス −1）
- `verify_agent_guard.ps1` のクロスハーネステスト削除

---

## 4. 実装済み: Harness Baseline（セットアップ固定）

### 4.1 方針

**セットアップで機械固定 → ルールで「触るな」→ 監査で drift 検知**

エージェントはセッション開始時に以下を**すでに成立している**前提で動く。タスク中に `settings.json`、シェルプロファイル、Windows PATH を変更しない。

### 4.2 固定される内容

| 層 | 内容 | SSOT |
| :--- | :--- | :--- |
| Agent Shell | `pwsh.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass` | `configs/cursor/harness-settings.json` |
| automation env | `PYTHONUTF8`, `GIT_PAGER=cat`, `DOTFILES_HARNESS=cursor-windows-v1`, telemetry off | 同上 |
| ファイル encoding | `files.encoding: utf8` | 同上 |
| User PATH | `~/.local/bin` 先頭 | `scripts/setup_cursor_harness.ps1` |
| User env | 上記と同期（Cursor 外の subprocess にも効く） | 同上 |
| Hooks / rules | 従来どおり `just sync-rules` | `configs/agents/` |
| マニフェスト | `~/.cursor/harness-baseline.json` | setup 時に書き込み |

### 4.3 追加・変更ファイル

| ファイル | 変更 |
| :--- | :--- |
| `configs/cursor/harness-settings.json` | **新規** — Cursor User settings 断片 SSOT |
| `configs/cursor/agent-shell.json` | legacy 互換（harness-settings 優先時は未使用） |
| `scripts/setup_cursor_harness.ps1` | **新規** — env + PATH + merge + manifest |
| `scripts/merge_cursor_agent_shell.py` | harness-settings 優先、automationProfile.env deep merge |
| `scripts/04_setup_configs.ps1` | Step 4.4 で setup_cursor_harness 呼び出し |
| `configs/agents/HARNESS_BASELINE.md` | **新規** — エージェント向け前提一覧 |
| `configs/agents/GLOBAL_RULES.md` | Harness baseline 不変条件を先頭付近に追加 |
| `justfile` | `setup-harness` / `check-harness` |
| `tests/verify_tools.ps1` | baseline / DOTFILES_HARNESS / settings 同期チェック |
| `AGENTS.md` | コマンド表に setup-harness 追記 |

### 4.4 セットアップフロー

```text
just install (step 4)
    │
    ├─ 04_setup_configs.ps1 … dotfiles deploy
    ├─ sync_agent_rules.ps1 … hooks, AGENTS.md, skills, settings merge
    └─ setup_cursor_harness.ps1 (step 4.4)
           ├─ User 環境変数
           ├─ User PATH (~/.local/bin)
           ├─ harness-settings → %APPDATA%/Cursor/User/settings.json
           └─ ~/.cursor/harness-baseline.json
```

### 4.5 運用コマンド

```powershell
just setup-harness    # 再適用（drift 修復）
just check-harness    # 検査のみ（exit 1 = drift）
just audit            # verify_tools に baseline チェック含む
```

### 4.6 エージェント不変条件（GLOBAL_RULES 要約）

> Harness baseline (pre-configured): `just install` / `just deploy` + `just sync-rules` でプロビジョン済み。Agent Shell・hooks・PATH・UTF-8 は固定。**ユーザー明示指示なしに再設定しない。** 詳細: `configs/agents/HARNESS_BASELINE.md`

---

## 5. 次セッション候補（優先度）

| 順 | 作業 | 効果 |
| :---: | :--- | :--- |
| 1 | `GUARD_POLICY.md` 新設 + GLOBAL_RULES のゲート列挙削除 | soft 肥大解消 |
| 2 | `sync-rules -Profile Cursor` | 同期時間・複雑度削減 |
| 3 | `adapters/cursor.py` 切り出し | monofile 縮小 |
| 4 | rtk hook を guard 内統合 | Shell フック 1 プロセス化 |

---

## 6. 関連メモリ

`just remember` に保存済み:

- **Q**: agent harness guardrails bloat causes and appropriateness  
- **A**: 積層 v2-v4.7、二重壁意図的、deny 2.9%、債務は monofile + echo + test mirror

---

## 7. 参照

- 運用 SSOT: `configs/agents/HARNESS_BASELINE.md`
- グローバルルール: `configs/agents/GLOBAL_RULES.md`
- ガード実装: `scripts/agent_guard.py`（v4.7 ヘッダ changelog）
- セッションログ: `just session-report` → `graphify-out/session-log.jsonl`
