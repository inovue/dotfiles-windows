# Manual Logo / Wordmark Validation (Real API E2E)

Automated gates catch empty crops and bad seams. **Human review** is still required for legibility, brand fit, and glow artifacts.

## Prerequisites

```powershell
just sync-rules
$env:FAL_KEY = "<your-key>"   # or: just setup-keys
Set-Location "$env:USERPROFILE\.cursor\skills\asset-generator"
```

## Step 1 — Write `cells.json`

Use explicit `id` slugs for every logo variant:

```json
[
  { "id": "bevel_wordmark", "prompt": "Cell A: two-line FINANCIAL / FANTASY wordmark, white #fff, cyan #70d0f8 glow, FFVII beveled frame" },
  { "id": "flat_vector", "prompt": "Cell B: flat indigo vector wordmark matching app palette" },
  { "id": "minimal_sans", "prompt": "Cell C: minimal geometric sans-serif lockup" },
  { "id": "glass_badge", "prompt": "Cell D: glassmorphism circular badge with monogram" }
]
```

## Step 2 — Visual Grill (dry-run)

```powershell
.\run.ps1 --print-prompt --preset logo -g 4 "Financial Fantasy Logos" -s flat `
  --items cells.json -r ../public/favicon.svg -m style
```

**Agent must verify before `--confirm`:**

- [ ] Brand colors pulled from codebase (`global.css`, `site-config`)
- [ ] Style preset has explicit (Recommended) rationale
- [ ] Each cell uses a **concrete physical metaphor** (not "modern logo")
- [ ] Every `[Row, Col]` line matches user intent
- [ ] CONFIRM TOKEN copied unchanged
- [ ] GRILL_ACK copied from dry-run output (required for `--grill-ack`)

## Step 3 — Generate

```powershell
.\run.ps1 --confirm <TOKEN> --grill-ack <GRILL_ACK> --preset logo -g 4 "Financial Fantasy Logos" -s flat `
  --items cells.json -r ../public/favicon.svg -m style --out out/logos-v1
```

For blue/cyan glow that rembg eats:

```powershell
.\run.ps1 --confirm <TOKEN> --preset logo -g 4 "Logos" --no-rembg --tight --items cells.json --out out/logos-chroma
```

Horizontal wordmarks (8 variants):

```powershell
.\run.ps1 --confirm <TOKEN> --preset wordmark -g 4x2 "Brand Wordmarks" --items cells-8.json --out out/wordmarks-v1
```

## Step 4 — Automated inspect (no API)

```powershell
.\run.ps1 --inspect out/logos-v1
```

Target: **≥ 75/100 (grade B)**. Inspect checks files, alpha fill, dimensions, seam detector.

```powershell
.\run.ps1 --inspect out/logos-v1 -j   # JSON for agents
```

## Step 5 — Human visual checklist

Open each `.webp` at **128px display width** (browser devtools or Figma):

| Check | Pass criteria |
|:---|:---|
| Full wordmark | No truncated fragments (`CIAL` instead of `FINANCIAL`) |
| Text legibility | Readable at 128px width without zoom |
| Color match | Within brand palette (compare to favicon / CSS tokens) |
| Edge cleanliness | No magenta/gray seam residue on borders |
| Glow preservation | Cyan/blue glow intact (if `--no-rembg` used) |
| Filename match | `01_bevel_wordmark.webp` maps to correct cell prompt |

### Recorded session (2026-08-30)

Batch `tests/fixtures/out/live-logos/` (`asset_ww4edu`): **3/4 PASS** — Cell C (`03_minimal_lockup.webp`) showed a monogram "N" instead of full FINANCIAL FANTASY text despite automated score 96/100. Re-prompt with anti-monogram guard in `cells-live-logos.json` and re-run.

**2026-08-30 runs 2–3:** Cell C failed twice more (shield icon, then "N"). **Fix:** use two-line `FINANCIAL` / `FANTASY` layout for Cell C (same pattern as A/B) — single-line minimal lockups have high gpt-image-2 drift.

## Step 6 — Retry decision tree

```text
inspect FAIL (seam detector ≠ magenta)
  → Re-run with --mq high; do NOT use --allow-weak-seams unless desperate

inspect FAIL (alpha < 2%)
  → Try --no-rembg --tight for logos; check cells.json prompts

inspect WARN (logo/wordmark ink < 10%)
  → Re-prompt with bold opaque letterforms; logo preset now scales fragment fallback via contain

inspect PASS but human FAIL (truncated text)
  → Add "full wordmark centered with 20% margin" to cell prompt
  → For single-letter/monogram outputs: add "NOT a monogram, FULL WORDS spelled out"
  → Re-run --print-prompt (new token) → --confirm

inspect PASS but human FAIL (wrong style)
  → Adjust -s preset or -r reference; re-grill with user
```

## Step 7 — Ship to project

Copy passing assets into the target repo:

```text
src/assets/images/generated/<batch>/
```

`manifest.json` records `confirmToken`, `cellSpecs`, and `quality` for audit.

## CI / regression (dotfiles repo)

```powershell
just test-asset-generator          # unit tests only (no API)
just test-asset-generator-live     # full fal.ai 2x2 smoke (costs credits; needs FAL_KEY)
```
