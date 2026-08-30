---
name: asset-generator
description: LP/web batch asset generator with grid-splitting, quality gates, and Windows-safe cells.json workflow. Square icons (2x2/3x3) and horizontal wordmarks (-g 4x2 --preset wordmark).
version: 2.0.4
license: MIT
allowed-tools:
  - Bash(powershell -File <skill-dir>/run.ps1 *)
  - Bash(node <skill-dir>/node_modules/tsx/dist/cli.mjs <skill-dir>/src/cli.ts *)
---

# Asset Generator — Agent Visual Director & Grill Playbook

Repo SSOT: `configs/agents/skills/asset-generator/`. Deploy: `just sync-rules` → `~/.cursor/skills/asset-generator/` (**runs `pnpm install` automatically**).

## Windows Setup

```powershell
just sync-rules   # sync + pnpm install
$skill = "$env:USERPROFILE\.cursor\skills\asset-generator"
Set-Location $skill
.\run.ps1 --help   # Windows-safe runner (never use npx tsx)
```

If `sharp` fails: `pnpm approve-builds esbuild sharp` (once).

---

## 🛑 MANDATORY WORKFLOW

```text
1. Write cells.json (with explicit ids for logos)
2. .\run.ps1 --print-prompt -g 4 "Theme" --items cells.json --out out
3. User confirms all [Row, Col] lines + GRILL CHECKLIST
4. .\run.ps1 --confirm <TOKEN> --grill-ack <GRILL_ACK> -g 4 "Theme" --items cells.json --out out
```

> Grid generation **without `--confirm` exits with error.** Inline `--items '[...]'` is **blocked on Windows.**

### Flag lock (dry-run ↔ generate)

The CONFIRM TOKEN is a SHA256 digest of **every** bound flag: theme, grid, cells, style, preset, refs, format, quality, and **`--out` path**.

- **Dry-run and `--confirm` must use identical flags.** Copy the full generate command from dry-run output.
- **Any flag change** (including adding `--out`, `-r`, `-f`, or `-q`) → **re-run `--print-prompt`** and use the new token.
- **Always pass `--out`** on both steps so output path is stable and token-bound (never rely on random `Pictures/assets/...` defaults).

### Reference images (`-r`)

- **Only when the user explicitly provides a path or asks for style/UI anchoring.** Do not add `-r` proactively.
- If generation fails with fal.ai **422** on edit: retry without `-r` (falls back to `gpt-image-2` generate) or fix refs and re-run dry-run.

### Windows output flag

- Prefer **`--out`** in agent commands (explicit, unambiguous). Short `-o` works after v2.0.3 (`run.ps1` uses `$args` passthrough).

### cells.json format

```json
[
  {
    "id": "window_bevel",
    "prompt": "Cell A: two-line FINANCIAL / FANTASY wordmark, white #ffffff top, cyan #70d0f8 glow below, FFVII beveled window frame"
  },
  {
    "id": "crystal_flat",
    "prompt": "Cell B: flat crystal vector wordmark matching app indigo palette"
  },
  { "id": "minimal", "prompt": "Cell C: minimal sans-serif wordmark" },
  { "id": "glass_badge", "prompt": "Cell D: glassmorphism logo badge" }
]
```

`id` becomes the filename stem (`01_window_bevel.webp`). Strings-only arrays also work; `Cell A:` prefixes auto-extract ids.

---

## ⚡ Commands

```powershell
$skill = "$env:USERPROFILE\.cursor\skills\asset-generator"
Set-Location $skill

# Dry-run — copy CONFIRM TOKEN + GRILL_ACK; include --out before token is final
.\run.ps1 --print-prompt -g 4 "Financial Fantasy Logos" -s flat `
  --items cells.json --out src/assets/images/generated/logos

# With refs (user-requested only) — same --out on both steps
.\run.ps1 --print-prompt -g 4 "Financial Fantasy Logos" -s flat `
  --items cells.json -r ../public/favicon.svg -m style `
  --out src/assets/images/generated/logos

# Generate — paste token from dry-run; flags must match exactly
.\run.ps1 --confirm abc123def456 --grill-ack <GRILL_ACK> --preset logo -g 4 "Financial Fantasy Logos" -s flat `
  --items cells.json -r ../public/favicon.svg -m style `
  -f png --out src/assets/images/generated/logos

# Blue/cyan logos — chroma-key only
.\run.ps1 --confirm <TOKEN> --grill-ack <GRILL_ACK> -g 4 "Logos" --no-rembg --tight `
  --items cells.json --out out

# Horizontal wordmarks — 4x2 landscape cells
.\run.ps1 --print-prompt -g 4x2 "Brand Wordmarks" --preset wordmark --items cells-8.json --out out
.\run.ps1 --confirm <TOKEN> --grill-ack <GRILL_ACK> -g 4x2 "Brand Wordmarks" --preset wordmark `
  --items cells-8.json --out out

# Post-generation validation (no API)
.\run.ps1 --inspect out
```

### Single hero

```powershell
.\run.ps1 --print-prompt "AI Workspace" -s glass -a 16:9 -l right-heavy --out hero.webp
.\run.ps1 --confirm <TOKEN> "AI Workspace" -s glass -a 16:9 -l right-heavy --out hero.webp
```

---

## Key Options

| Option | Notes |
|:---|:---|
| `--items cells.json` | **Required** for grids — plain `.json` path OK (PowerShell eats `@`) |
| `--confirm <token>` | **Required** — token from dry-run CONFIRM TOKEN line |
| `--grill-ack <token>` | **Required** — GRILL_ACK from dry-run (checklist completed) |
| `--out <path>` | **Required for stable tokens** — output dir (grid) or file (single hero). Use on dry-run **and** generate. |
| `-f png` / `-f jpeg` | Cell output: `webp` (default), `png`, `jpeg`/`jpg`. Token binds format+quality+`--out`. JPEG blocked for logo/wordmark unless `--allow-jpeg-logos`. |
| `--inspect <dir>` | Validate existing batch (score /100); no API call |
| `--mq md` / `--mq medium` | gpt-image-2 render quality (default **md**). Aliases: `low`, `high`. Logo/wordmark preset forces `high`. |
| `-k` / `--2k` | 2K sheet (2048px). Default is **1K** (`square_hd` / 1024px presets). |
| `--preset wordmark` | `--mq high --tight` + landscape wordmark prompt hints; use with `-g 4x2` |
| `--allow-weak-seams` | Override magenta seam quality gate (risky) |
| `--tight` | Chroma-key + largest-subject crop |
| `--no-rembg` | Chroma-key sheet instead of fal rembg (blue glow) |
| `-r` / `-m style` | Anchor to favicon / UI screenshot — **user-requested only** |
| `-g 2x4` | NxM grids supported |

---

## Artifacts

```text
<out>/
├── sheet.raw.png
├── sheet.grid.json
├── sheet.transparent.png
├── 01_window_bevel.webp   # or .png / .jpg per -f
└── manifest.json   # prompt, itemsList, cellSpecs, quality, confirmToken
```

Troubleshooting: `references/troubleshooting.md` · Grill: `references/grill-guide.md` · Manual E2E: `references/manual-validation.md` · Scoring: `references/quality-rubric.md`
