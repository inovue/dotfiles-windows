import path from 'node:path';
import fs from 'node:fs';
import type { AssetManifest, GeneratorOptions } from './types.js';
import { buildPrompt } from './prompt.js';
import { ensureDirSync, generateBatchId, parseOutPath, resolveDigestOutDir } from './paths.js';
import { generateFalImage } from './fal.js';
import { DEFAULT_MODEL_QUALITY } from './types.js';
import { detectGridSeams } from './grid-detect.js';
import { removeBackground } from './rembg.js';
import { clearSeamCorridors, extractAndSaveAssets } from './pack.js';
import { chromaKeyImageFile } from './chroma.js';
import { validateGridSeams, PipelineValidationError } from './validate.js';
import { ItemsParseError } from './items.js';

function validateRefImages(options: GeneratorOptions): void {
  const refs = options.refImages ?? [];
  if (refs.length === 0) return;

  const missing = refs.filter((p) => !fs.existsSync(p));
  if (missing.length > 0) {
    throw new PipelineValidationError(
      `Reference image(s) not found:\n${missing.map((p) => `  - ${p}`).join('\n')}`,
    );
  }
}

export async function runAssetGenerator(options: GeneratorOptions): Promise<AssetManifest> {
  const batchId = generateBatchId();
  const { outDir, customFilename } = parseOutPath(options.outDir, batchId);
  options.customFilename = customFilename;
  options.outDirResolved = resolveDigestOutDir(options.outDir);
  ensureDirSync(outDir);

  validateRefImages(options);

  const { prompt, gridInfo, itemsList, cellSpecs, confirmToken, grillAckToken } = buildPrompt(options);

  if (options.printPrompt) {
    if (options.jsonOutput) {
      console.log(JSON.stringify({ prompt, gridInfo, itemsList, cellSpecs, confirmToken, grillAckToken }, null, 2));
    } else {
      console.log('\x1b[33m--- GENERATED PROMPT ---\x1b[0m');
      console.log(prompt);
      if (gridInfo.total > 1) {
        console.log('\x1b[33m--- CELLS PREVIEW ---\x1b[0m');
        for (let i = 0; i < cellSpecs.length; i++) {
          const spec = cellSpecs[i];
          const idPart = spec.id ? `id=${spec.id} | ` : '';
          const preview = spec.prompt.length > 80 ? `${spec.prompt.slice(0, 80)}…` : spec.prompt;
          console.log(`  [${i + 1}] ${idPart}${preview}`);
        }
      }
      console.log('\x1b[33m--- OUTPUT ---\x1b[0m');
      console.log(`  format: ${options.format}  quality: ${options.quality}`);
      if (options.outDirResolved) {
        console.log(`  out: ${options.outDirResolved}`);
      } else {
        console.log('  out: (default Pictures/assets — not bound to token; pass --out for stable path)');
      }
      console.log('\x1b[33m--- GRILL CHECKLIST (verify before --confirm) ---\x1b[0m');
      console.log('  [ ] Brand colors from codebase (global.css / site-config)');
      console.log('  [ ] Style preset chosen with (Recommended) rationale');
      console.log('  [ ] Each cell has concrete physical metaphor (not abstract)');
      console.log('  [ ] Every [Row, Col] line matches user intent');
      console.log('\x1b[33m--- CONFIRM TOKEN ---\x1b[0m');
      console.log(`  ${confirmToken}`);
      console.log('\x1b[33m--- GRILL_ACK (required for generation) ---\x1b[0m');
      console.log(`  ${grillAckToken}`);
      console.log('\x1b[33m--- NEXT STEP ---\x1b[0m');
      console.log(`Re-run without --print-prompt and add:  --confirm ${confirmToken}  --grill-ack ${grillAckToken}`);
      console.log('\x1b[33m------------------------\x1b[0m');
    }
    process.exit(0);
  }

  const log = (msg: string) => {
    if (!options.jsonOutput) console.log(msg);
    else process.stderr.write(msg + '\n');
  };

  const warn = (msg: string) => {
    if (!options.jsonOutput) console.warn(`\x1b[33m[WARN] ${msg}\x1b[0m`);
    else process.stderr.write(`[WARN] ${msg}\n`);
  };

  if (options.tight && (options.modelQuality || DEFAULT_MODEL_QUALITY) === 'low' && options.preset !== 'logo' && options.preset !== 'wordmark') {
    warn('--tight with modelQuality=low — use --preset logo or --mq high for logos.');
  }

  if (options.format === 'jpeg' && (options.preset === 'logo' || options.preset === 'wordmark') && options.allowJpegLogos) {
    warn('JPEG with logo/wordmark — transparency flattened to white (#ffffff). Prefer webp or png.');
  }

  log(`\x1b[32m🚀 Starting Asset Generation [${batchId}]\x1b[0m`);
  log(`📂 Output Directory: \x1b[34m${outDir}\x1b[0m`);
  log(`🎨 Mode: ${gridInfo.total > 1 ? `Grid ${gridInfo.rows}x${gridInfo.cols} (${gridInfo.total} items)` : 'Single Image'}`);
  if (options.style) log(`✨ Style: ${options.style}`);
  if (options.preset) log(`📋 Preset: ${options.preset}`);
  log(`📁 Output format: ${options.format} (quality ${options.quality})`);
  if (options.is2k) log(`🔍 Resolution: 2K (2048×2048)`);
  else log(`🔍 gpt-image-2: 1K tier (1024px presets)`);
  if (gridInfo.total > 1) {
    const pad = options.pad ?? 10;
    if (options.tight) log(`📐 Framing: Tight chroma-key trim`);
    else if (options.rawCell) log(`📐 Framing: Raw Cell Bounds`);
    else log(`📐 Framing: Normalized Square Canvas (Padding: ${pad}%)`);
  }

  const rawPath = path.join(outDir, 'sheet.raw.png');
  await generateFalImage(prompt, rawPath, options);
  log(`✅ Raw image generated: ${rawPath}`);

  log('🔍 Detecting grid seams and bounding boxes...');
  const gridMeta = await detectGridSeams(rawPath, gridInfo.cols, gridInfo.rows);
  validateGridSeams(gridMeta, { allowWeakSeams: options.allowWeakSeams });
  if (gridMeta.detector !== 'magenta') {
    warn(`Seam detector: ${gridMeta.detector} (${gridMeta.magentaSeamHits}/${gridMeta.totalSeams} magenta hits)`);
  }
  const gridMetaPath = path.join(outDir, 'sheet.grid.json');
  fs.writeFileSync(gridMetaPath, JSON.stringify(gridMeta, null, 2) + '\n');
  log(`✅ Grid geometry saved: ${gridMetaPath} (detector: ${gridMeta.detector})`);

  let processedBuffer: Buffer;
  const transparentPath = path.join(outDir, 'sheet.transparent.png');

  if (options.rembg !== false) {
    await removeBackground(rawPath, transparentPath);
    log(`✅ Background removed: ${transparentPath}`);

    if (gridInfo.total > 1) {
      log('🧹 Clearing seam corridors (geometry-safe zeroing)...');
      processedBuffer = await clearSeamCorridors(transparentPath, gridMeta);
    } else {
      processedBuffer = fs.readFileSync(transparentPath);
    }
  } else {
    log('🎨 Skipping rembg — applying chroma-key (#C0C0C0 / #FF00FF)...');
    await chromaKeyImageFile(rawPath, transparentPath);
    log(`✅ Chroma-keyed sheet: ${transparentPath}`);

    if (gridInfo.total > 1) {
      log('🧹 Clearing seam corridors...');
      processedBuffer = await clearSeamCorridors(transparentPath, gridMeta);
    } else {
      processedBuffer = fs.readFileSync(transparentPath);
    }
  }

  log('📦 Normalizing, splitting & packing assets...');
  const manifest = await extractAndSaveAssets(
    processedBuffer,
    gridMeta,
    outDir,
    options,
    itemsList,
    batchId,
    prompt,
    cellSpecs,
  );

  manifest.confirmToken = confirmToken;
  manifest.gridDetector = gridMeta.detector;
  manifest.preset = options.preset;
  const coverages = manifest.items.map((i) => i.alphaCoverage).filter((v): v is number => v != null);
  const widths = manifest.items.map((i) => i.width);
  const heights = manifest.items.map((i) => i.height);
  manifest.quality = {
    gridDetector: gridMeta.detector,
    seamConfidence: gridMeta.seamConfidence,
    magentaSeamHits: gridMeta.magentaSeamHits,
    totalSeams: gridMeta.totalSeams,
    alphaGateMin: 0.02,
    minAlphaCoverage: coverages.length > 0 ? Math.min(...coverages) : undefined,
    minWidth: widths.length > 0 ? Math.min(...widths) : undefined,
    minHeight: heights.length > 0 ? Math.min(...heights) : undefined,
    dimensionGateMin: 32,
    cellsPassed: manifest.items.length,
  };
  fs.writeFileSync(
    path.join(outDir, 'manifest.json'),
    JSON.stringify(manifest, null, 2) + '\n',
  );

  log(`\x1b[32m✨ Done! Generated ${manifest.items.length} asset(s) in ${outDir}\x1b[0m`);
  for (const item of manifest.items) {
    const cov = item.alphaCoverage != null ? `, ${(item.alphaCoverage * 100).toFixed(1)}% fill` : '';
    log(`   📄 ${item.filename} (${item.width}x${item.height}${cov}) - ${item.label}`);
  }

  if (manifest.quality && !options.jsonOutput) {
    const q = manifest.quality;
    log(`\n\x1b[36m📊 Quality Report\x1b[0m`);
    log(`   Seam: ${q.gridDetector} (${q.magentaSeamHits ?? '?'}/${q.totalSeams ?? '?'} magenta)`);
    if (q.minAlphaCoverage != null) {
      log(`   Min alpha: ${(q.minAlphaCoverage * 100).toFixed(1)}%`);
    }
    if (q.minWidth != null && q.minHeight != null) {
      log(`   Min dimension: ${q.minWidth}x${q.minHeight}px`);
    }
    log(`   Run: .\\run.ps1 --inspect ${outDir}`);
  }

  if (options.jsonOutput) {
    console.log(JSON.stringify(manifest, null, 2));
  }

  return manifest;
}
