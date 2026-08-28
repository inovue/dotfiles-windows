# SOTA Cursor Agent — Harness Strategy (2026-08-28 → v2)

Cursor 専用。graphify + rtk に 100% 依存。速度・トークン・コードベース把握・自律グラフ維持を同時に最大化する。

**固定判断 (grill):** Cursor-only / stop 強制ループ / graphifyy 0.9.50・rtk 0.45.0 厳密ピン。

---

## 1. 目標

| 軸 | SOTA の意味 | 実装 |
| :--- | :--- | :--- |
| 速度 | フック二重起動ゼロ（Project が graph 壁、User は destructive Shell のみ）、pwsh -NoProfile | Cursor 公式: 全ソースが実行される。full guard を二本置くと Read crawl が二重計上される |
| トークン | 観測圧縮 + ルール短文化 + グラフ検索 | `rtk rewrite` → `updated_input`、always-on <100 行、skills on-demand |
| 把握 | grep の代わりにグラフ走査 | `just hubs/neighbors/path/affected/explain` + MCP |
| 自律 | バッチ末尾でグラフが古いまま終わらない | stop `loop_limit` 5 で update-graph / audit / semantic-merge を掬う |
| 再現 | ツールドリフトで「昨日の agent」に戻らない | `configs/pins.json` + audit deny |

参照アーキテクチャ: OpenHands V1（不変 config / イベントソーシング相当の session-log / 圧縮は観測側）、Cursor 公式 hooks（`updated_input` / `followup_message` / `sessionStart.additional_context`）、Graphify-Labs CLI、rtk-ai rewrite hook。

---

## 2. なぜ前版は SOTA でなかったか

| ギャップ | 実害 |
| :--- | :--- |
| マルチハーネス ACI | `agent_guard` 肥大と sync の系統 diff が主因 |
| `rtk hook cursor` が独立 preToolUse | Shell あたりプロセス +1。deny-retry はさらに +1 ターン |
| stop は one-shot リマインド | エージェントが無視するとグラフが腐る |
| graphify の affected / diagnose / tree / benchmark 未配線 | 「全機能依存」が query/path/god-nodes だけ |
| graphifyy / rtk が latest 追従 | 再現不能 |
| GLOBAL_RULES がゲート一覧を再記述 | soft/hard エコー、トークン浪費 |
| Graphify MCP がこのセッションの dynamic catalog に無い | `just graph` fallback が本線。ルールは MCP 前提のまま |

---

## 3. 層構造 (v2)

```text
SOFT  always-on (<100 lines)          HARD  deterministic
GLOBAL_RULES.md  文化・手順ポインタ     agent_guard.py v5
graphify.mdc     1 画面の graph 手順    Cursor hooks.json
HARNESS_BASELINE セットアップ済み前提    rtk rewrite (in-guard)
GUARD_POLICY.md  ゲート表 SSOT          pins.json + audit
        │                                      ▲
        │ just sync-rules (Cursor only)        │ sessionStart / preToolUse /
        v                                      │ beforeMCP / afterFileEdit /
~/.cursor/rules, skills, hooks, AGENTS.md      │ stop (loop_limit 5)
```

Skills (on-demand): `graphify-navigator`（全 CLI）、`graphify-builder`（semantic）、`rtk-expert`（rewrite/gain/smart）。

---

## 4. Cursor hook トポロジ

公式: `preToolUse` は `updated_input` 可。`beforeShellExecution` は書換不可 → **書換は preToolUse**。`stop.followup_message` + `loop_limit` 5。`sessionStart` は block 不可。`beforeMCPExecution` は Cloud で欠ける → preToolUse `MCP:` と query-log 180s でカバー。

| Hook | Guard 動作 |
| :--- | :--- |
| sessionStart | pins + graph-first を additional_context に注入 |
| preToolUse | 破壊 deny / グラフ壁 / 読み予算 / **rtk rewrite** |
| beforeMCPExecution | graphify 接触記録。未知サーバは落とさない（fail-open、グラフ接触のみ） |
| afterFileEdit | edited フラグのみ |
| stop | 未検証バッチなら followup。最大 5 周 |
| sessionEnd | 同じ文面を advisory |

二重壁: プロンプトは「hooks が壁」とだけ言い、詳細は GUARD_POLICY。

---

## 5. Graphify 全機能マップ

エンジン 0.9.50。**使わないもの:** `graphify extract`（第二 LLM）、`graphify … install` の vendor ルール導入（SSOT 破壊）。

| 意図 | コマンド |
| :--- | :--- |
| 質問 | `just graph "<q>"` → `graphify query --budget 1200` |
| ハブ | `just hubs` → `god-nodes` |
| 近傍 | `just neighbors` → `explain` |
| 経路 | `just path A B` |
| 影響範囲 | `just affected X` → `graphify affected` |
| 診断 | `just diagnose` → `diagnose multigraph` |
| 木 | `just graph-tree` → `tree` |
| トークン比較 | `just graph-bench` → `benchmark` |
| AST 更新 | `just update-graph` (`update --force` + rehydrate) |
| semantic | builder skill → `just semantic-merge` |
| 記憶 | `just lessons` / `just remember` |
| 監視 | `just watch` |
| MCP | query_graph / get_node / get_neighbors / shortest_path / god_nodes / get_community / graph_stats。必ず `project_path` + `token_budget: 1200` |

---

## 6. RTK 全機能マップ

エンジン 0.45.0。公式 Cursor 統合は `rtk init -g --agent cursor` だが、当ハーネスは **guard 内 `rtk rewrite`** に一本化（プロセス -1）。

| 意図 | コマンド |
| :--- | :--- |
| 自動圧縮 | 生 `git status` 等 → hook が `rtk git status` に書換 |
| 読む | `rtk read` / `rtk read -l aggressive` / `rtk smart` |
| 探す | `rtk rg` / `rtk find` |
| テスト | `rtk test` / `rtk pytest` |
| 分析 | `just rtk-gain` / `rtk gain --history` / `rtk discover` |
| パイプ | `rtk pipe` |
| 超圧縮 | `rtk --ultra-compact …`（必要時のみ） |

組み込み Read/Grep は Bash hook を通らない（公式）。巨大ファイルは Shell の `rtk read` を使え。

---

## 7. 環境固定

| 層 | 値 | SSOT |
| :--- | :--- | :--- |
| Harness id | `cursor-windows-v2` | `configs/pins.json` + `harness-settings.json` |
| Agent Shell | `pwsh -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass` | harness-settings |
| graphifyy | `==0.9.50` extras mcp,gemini,openai,anthropic | `03_setup_runtimes.ps1` |
| rtk | GitHub release `v0.45.0` + SHA pin | 同上 + Assert-PinnedHash |
| MCP | workspace `.cursor/mcp.json` が repo `graph.json` をピン。global は unpin | sync-rules |
| PATH | `~/.local/bin` 先頭 | setup_cursor_harness |
| テレメトリ | off。`RTK_TELEMETRY_DISABLED=1` | harness env |

アップグレードは `configs/pins.json` を先に上げてから `just update-graphify` / `just update-rtk`。latest 追従は禁止。

---

## 8. エージェントループ（毎回）

```text
sessionStart context
  → just lessons（人間/エージェントがセッション頭で）
  → 調査: just audit → hubs → neighbors/affected
  → 改修: checkpoint → path → scoped rg → edit
  → バッチ末: just update-graph → (docsなら builder+semantic-merge) → just audit
  → stop が未了なら followup（最大 5）
```

MCP が catalog に無いセッションでは `just graph` を MCP の代替として使う。再試行で MCP を叩かない。

---

## 9. 破壊的変更 (v1 → v2)

- `sync-rules` は Cursor ターゲットのみ。MCP テンプレは `configs/agents/cursor/mcp_config.json`。
- `rtk hook cursor` を hooks.json から削除。
- stop の batch-end は one-strike ではない（ハードループ）。
- noisy git は deny-retry ではなく rewrite-allow。
- `DOTFILES_HARNESS=cursor-windows-v2`。
- `just update-graphify` / `update-rtk` はピン版を入れる（最新へ上げない）。

---

## 10. 検証

| チェック | コマンド |
| :--- | :--- |
| ピン | `just check-pins`（graphify 0.9.50 / rtk 0.45.0 / harness v2） |
| ガード | `tests/verify_agent_guard.ps1` v5（rewrite + hard-loop + sessionStart） |
| 全体 | `just audit` |

---

## 11. 参照

- Cursor: https://cursor.com/docs/hooks https://cursor.com/docs/cli/overview https://cursor.com/docs/rules
- Graphify: https://github.com/Graphify-Labs/graphify （CLI `graphify --help`）
- RTK: https://github.com/RTK-AI/rtk （`rtk rewrite` / `rtk hook cursor`）
- 運用: `configs/agents/HARNESS_BASELINE.md` `GUARD_POLICY.md` `GLOBAL_RULES.md`
