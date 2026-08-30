# Asset Generator Troubleshooting & Operations

### 1. Missing `FAL_KEY`
- **Symptom**: `[ERROR] FAL_KEY is not set`.
- **Fix**: `just setup-keys` or `$env:FAL_KEY = "your_key"`.

### 2. Windows: `EBADDEVENGINES` / `ERR_PNPM_IGNORED_BUILDS`
- **Fix**:
  ```powershell
  just sync-rules
  Set-Location "$env:USERPROFILE\.cursor\skills\asset-generator"
  pnpm approve-builds esbuild sharp   # once, if needed
  .\run.ps1 --help
  ```

### 3. `[ITEMS ERROR] Cell count mismatch` or `Grid generation blocked`
- **Cause**: Missing `--confirm`, wrong cell count, or inline JSON on Windows.
- **Fix**: `cells.json` + `--items cells.json`. Run `--print-prompt` first, then `--confirm`.

### 4. Inline JSON blocked on Windows
- **Symptom**: `[ITEMS ERROR] Inline --items JSON is blocked on Windows`
- **Fix**: Always use `--items cells.json`. Never pass `'[...]'` inline in PowerShell.

### 5. Confirm token mismatch after dry-run
- **Cause**: CONFIRM TOKEN binds theme, cells, style, preset, refs, **`format`**, **`quality`** (default 80), and **`--out`** when set.
- **Fix**: Copy the **full** generate command from dry-run. Do not change `-f`, `-q`, `--out`, or `-r` between dry-run and `--confirm`.
- **Any flag change → re-run `--print-prompt`** and use the new token.
- Without `--out`, output goes to a random `Pictures/assets/.../asset_*` folder each run — **always pass `--out out/`** on dry-run and generate.
  ```powershell
  .\run.ps1 --print-prompt -g 4 "Theme" --items cells.json -f png --out out
  .\run.ps1 --confirm <TOKEN> --grill-ack <ACK> -g 4 "Theme" --items cells.json -f png --out out
  ```

### 6. PowerShell: `Parameter name 'o' is ambiguous`
- **Symptom**: `Possible matches: -OutVariable -OutBuffer` when using `-o` with `.\run.ps1`.
- **Cause**: Older `run.ps1` used `param()` / `[CmdletBinding()]`, which treats `-o` as a common parameter.
- **Fix**: `just sync-rules` (v2.0.3+ uses `$args` passthrough). Prefer **`--out`** in agent examples; `-o` also works after sync.

### 7. fal.ai 422 `image_urls` / `Field required` (edit with refs)
- **Symptom**: `Image Generation (openai/gpt-image-2/edit) failed … Unprocessable Entity` with `"loc": ["body", "image_urls"]`.
- **Cause**: Single `-r` reference used edit model without `image_urls` array (fixed in v2.0.3).
- **Fix**: `just sync-rules` to pick up fal.ts fix. Workaround: omit `-r` to use generate model, or re-run after sync.

### 8. `[QUALITY GATE] JPEG output is blocked for --preset logo/wordmark`
- **Cause**: JPEG flattens transparency onto white — unsuitable for default logo/wordmark workflow.
- **Fix**: Use `-f webp` or `-f png`. Only use JPEG for logos with explicit `--allow-jpeg-logos`.

### 9. Logo crop shows fragments (`CIAL` instead of full wordmark)
- **Cause**: rembg leaves low-alpha glow; naive alpha bbox picks seam debris.
- **Fix**: Use `--preset logo` or `--tight` (chroma-key `#C0C0C0`/`#FF00FF` then largest-subject bbox).
- **Also**: `--no-rembg` + `--tight` if rembg eats blue/cyan glow.

### 10. Seam Detection & Bounding Boxes
- Primary: magenta `#FF00FF` grid line scan.
- Fallback: equal-split geometry (blocked unless `--allow-weak-seams`).
- Inspect: `.\run.ps1 --inspect <outDir>` — target score ≥ 75/100.
- See `sheet.grid.json` for band coordinates.

### 11. Background Removal
- Default: `pixelcut/background-removal` (fallback: `birefnet`).
- Photo backgrounds / preserve gray sheet: `--no-rembg`.

### 12. Output formats (webp / png / jpeg)
- **webp** (default): transparent logos/icons — preferred for LP assets.
- **png**: lossless transparency when webp is undesirable.
- **jpeg**: no alpha; flattened onto `#ffffff`. Not for `--preset logo/wordmark` unless `--allow-jpeg-logos`.
- Inspect verifies file bytes match `manifest.outputFormat`. JPEG alpha **requires** `sheet.transparent.png` + `sheet.grid.json` bands (manifest `alphaCoverage` is not used for scoring).

### 13. Custom Output Directory
- Astro projects: `src/assets/images/generated/<batch>/` for `<Image />` ingestion.
- Use a **directory** for grids (`--out out/`), not `--out batch.jpg` (that path is for single-hero only).

### 14. Post-generation validation
- **Automated**: `.\run.ps1 --inspect out/batch` (no API call).
- **Manual**: `references/manual-validation.md` — human legibility checklist.
