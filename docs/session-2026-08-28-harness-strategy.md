# Cursor × rtk — 公式 hook のみ (2026-08-28)

Cursor 専用。自前ハーネス（agent_guard / 読み予算 / settings 強制）は置かない。
トークン削減は公式 `rtk hook cursor` の透過 rewrite だけ。

**固定判断:** Cursor-only / rtk ピンは `configs/pins.json`。知識グラフ (graphify) は配備しない。エージェント向け rtk skill は置かない。

---

## 1. 層

```text
SOFT  always-on                         HARD  (official rtk only)
GLOBAL_RULES.md  文化・手順ポインタ        ~/.cursor/hooks.json
        │                               command: rtk hook cursor
        │ just sync-rules               matcher: Shell
        v                               fail-open, never deny
~/.cursor/skills, AGENTS.md
```

Skills (on-demand): `modern-cli-expert`、`browser-agent`。

---

## 2. rtk の入れ方

バイナリは `scripts/03_setup_runtimes.ps1`（ピン）。hook は:

```powershell
rtk init -g --agent cursor --hook-only --auto-patch
```

`-g` は `init` のオプション。`--agent cursor` が無いと Claude 向けになる。
`--hook-only` は `~/.claude/RTK.md` を書かない。SSOT は `~/.cursor/hooks.json` を上書きしない。

アップグレードは `configs/pins.json` を先に上げてから `just update-rtk`。

---

## 3. 検証

```powershell
just check-pins
just check-rules
just audit
```
