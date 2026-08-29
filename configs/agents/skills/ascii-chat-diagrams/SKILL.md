---
name: ascii-chat-diagrams
description: >-
  Renders width-aligned ASCII/Unicode diagrams in chat for visual alignment —
  UI wireframes, comparison tables, bar charts, sparklines, and simple flows
  (hand-drawn). Python helper enforces monospace width (ASCII 1ch, CJK 2ch).
  Use when sketching layouts, comparing options, or aligning on UX/data before
  implementation. Not for HTML/CSS/SVG, nested layouts, or auto-generated
  architecture/state-machine diagrams.
---

# ASCII Chat Diagrams

Monospace diagrams for **recognition alignment** in chat. Output in a ` ```text ` block.

## Agent contract (minimal steps)

1. Draft to a UTF-8 **no-BOM** file (never eyeball spaces).
2. **One helper call** → write output to file (PowerShell stdout may strip trailing spaces):

```powershell
$ascii = "$env:USERPROFILE\.cursor\skills\ascii-chat-diagrams\scripts\ascii_diagram_helper.py"
[IO.File]::WriteAllText("draft.txt", $draft, [Text.UTF8Encoding]::new($false))
python $ascii autofit --mode pc --file draft.txt | Set-Content out.txt -Encoding utf8
```

3. Paste `out.txt` into ` ```text ` block. Optional one-line caption.

Repo SSOT: `configs/agents/skills/ascii-chat-diagrams/`. Deploy: `just sync-rules` → `~/.cursor/skills/`.

**PC 2-column:** `--split 22,55`. **Tablet:** `--split 15,38`. **PC 3-column:** `--split 20,30,26` (helper auto-fixes ±1).

---

## Canvas widths

| Mode | W | Use |
| :--- | :---: | :--- |
| **pc** | 80 | Dashboards, multi-column |
| **tablet** | 56 | Two-column |
| **sp** | 32 | Mobile single-column |
| **flow** | 120 | Horizontal flows |
| **inline** | 48 | Small chart/snippet |

Default **pc**. Multi-column: `Col1 + │ + Col2 = W - 2`.

---

## Commands

| Command | When |
| :--- | :--- |
| `autofit --mode pc --file draft.txt` | Full diagram (default) |
| `frame --title "X" --file content.txt` | Wrap lines in titled box |
| `table --headers "A,B" --rows "x,1\|y,2" --width 48` | Comparison table |
| `barchart --labels "A,B" --values "40,65" --width 40` | Bar chart rows |
| `sparkline --values "1,3,2,5" --width 24` | Trend snippet |
| `validate --mode pc --file diagram.txt` | Manual edits only |

All diagram commands **self-validate** (exit 1 if any line ≠ W).

---

## Notation (chat-safe)

| Control | ASCII |
| :--- | :--- |
| Button | `[ Deploy ]` |
| Input | `< Search... >` |
| Status | `{ OK }` / `{ ERR }` |
| Arrow | `--->` |

Nerd Font glyphs may show as □ in chat — use ASCII. Patterns: [references/component-patterns.md](./references/component-patterns.md).

---

## Anti-patterns

| Problem | Fix |
| :--- | :--- |
| Jagged border | **autofit**; never guess padding |
| Double-wrapped box | **autofit** skips already-valid framed input |
| `autofit` on `.md` | Extract ` ```text ` block first |
| Per-line shell calls | One `--file` per diagram |
| CJK as 1ch | Helper counts 2ch automatically |
| Nested box in frame | **frame** shrinks inner borders; or **autofit** pre-sized draft |

---

## Examples

- Chat-safe: [ascii-sp-dashboard.md](./examples/ascii-sp-dashboard.md), [ascii-comparison-table.md](./examples/ascii-comparison-table.md), [ascii-flow-login.md](./examples/ascii-flow-login.md)
- Nerd Font wireframes: [pc-dashboard.md](./examples/pc-dashboard.md), [tablet-two-column.md](./examples/tablet-two-column.md)
