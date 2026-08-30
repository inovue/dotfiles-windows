# Quality Rubric — Automated Scoring (0–100)

`--inspect <outDir>` computes this score from `manifest.json` + `sheet.grid.json`. **≥ 75 = production-ready for automated pipeline**; human review still required for brand fit.

## Breakdown

| Category | Max | Criteria |
|:---|:---:|:---|
| **Seam detection** | 25 | `magenta` = 25, `weak-magenta` = 12, `profile` = 8, `equal-split` = 0 |
| **Alpha coverage** | 25 | min cell fill: ≥15% = 25, ≥10% = 20, ≥5% = 15, ≥2% = 10 |
| **Dimensions** | 25 | min side: ≥128px = 25, ≥64px = 18, ≥32px = 12 |
| **Visual heuristics** | 15 | seam residue, aspect ratio, logo fragment detection |
| **Metadata (process)** | 25 | confirmToken (+5), all cell ids (+5), cellsPassed (+5), preset (+5) |

**`technicalScore`** = seam + alpha + dimensions + visual (max 90). **`total`** = normalized to /100.

## Grade scale

| Score | Grade | Meaning |
|:---:|:---:|:---|
| 90+ | A | Excellent — magenta seams, strong fill, large exports |
| 80–89 | B+ | Good — minor alpha or dimension headroom |
| **70–79** | **B** | **Shippable** with human spot-check |
| 60–69 | C+ | Usable icons; logos need retry |
| 50–59 | C | Weak seams or small crops — re-generate |
| <50 | D | Pipeline failure — do not ship |

## Version history (adversarial review)

| Version | Score | Notes |
|:---:|:---:|:---|
| v1.3 | ~40 | PowerShell JSON breakage, no gates |
| v1.5 | 58 | cells.json, chroma tight crop |
| v1.6 | 65 | confirm token, seam validation |
| v1.6.1 | 68 | hero confirm, manifest.quality |
| v1.7.0 | ~72 | wordmark preset, dimension gate |
| **v1.8.0** | **~76** | `--inspect`, scoring, manual-validation guide |
| **v1.8.1** | **~78** | live API E2E (`just test-asset-generator-live`), `just test-asset-generator` |
| **v1.8.2** | **~68** | logo live + 3-run stability; `technicalScore` split from process padding |
| **v1.9.0** | **~74** | visual inspect, wordmark 4x2 live |
| **v2.0.0** | **~79** | `--grill-ack`, 3x3 live, logo 3-run stability (spread 5) |
| **v2.0.1** | **~80** | logo contain-fallback; live logos **96/100** auto; human **3/4** (Cell C monogram fail) |

## Recorded human review (2026-08-30, live-logos batch `asset_ww4edu`)

128px-equivalent visual check against `manual-validation.md` Step 5:

| Cell | File | Full wordmark | Legibility | Edges | Verdict |
|:---|:---|:---:|:---:|:---:|:---:|
| A indigo_wordmark | `01_indigo_wordmark.webp` | FINANCIAL / FANTASY 2-line | OK | clean | **PASS** |
| B cyan_glow | `02_cyan_glow.webp` | FINANCIAL / FANTASY + glow | OK | clean | **PASS** |
| C minimal_lockup (run 1) | `03_minimal_lockup.webp` | **FAIL** — monogram "N" only | N/A | artifacts | **FAIL** |
| D glass_badge | `04_glass_badge.webp` | FF + FINANCIAL FANTASY | OK | clean | **PASS** |

**Run 4** (`asset_hf286d`, two-line Cell C): A/B/D **PASS**; C **FAIL** — monogram "N" persists in grid slot [2,1] despite prompt. **Mitigation:** swap charcoal wordmark to Cell A slot in fixture.

| **v2.0.2** | **~80 auto / ~75 human** | typography anti-drift rule; Cell C needs two-line prompt |

## What automation cannot score

- gpt-image-2 non-determinism (same prompt → different layouts)
- Typography kerning / letterform quality
- Brand semantic fit ("does this feel like our product?")

These require Step 5 in `manual-validation.md`.
