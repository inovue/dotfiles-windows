import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import type { AssetManifest, GridMeta, OutputFormat, GridBand } from './types.js';
import { inferOutputFormatFromFilename, sharpFormatForOutput } from './format.js';
import { measureAlphaCoverage, validateCellDimensions } from './validate.js';
import { measureCellVisuals, scoreVisualHeuristics } from './visual-inspect.js';

export interface InspectOptions {
  allowWeakSeams?: boolean;
  allowEmptyCells?: boolean;
  minAlpha?: number;
  minDimension?: number;
  json?: boolean;
}

export interface InspectFinding {
  level: 'error' | 'warn' | 'info';
  message: string;
}

export interface QualityBreakdown {
  seamDetection: number;
  alphaCoverage: number;
  dimensions: number;
  visualHeuristics: number;
  metadata: number;
  /** seam + alpha + dims + visual (no process padding) */
  technicalScore: number;
  /** confirmToken, ids, preset — workflow hygiene */
  processScore: number;
  total: number;
  grade: string;
}

export interface InspectResult {
  ok: boolean;
  outDir: string;
  manifest?: AssetManifest;
  gridMeta?: GridMeta;
  findings: InspectFinding[];
  breakdown: QualityBreakdown;
}

function gradeFromScore(score: number): string {
  if (score >= 90) return 'A';
  if (score >= 80) return 'B+';
  if (score >= 70) return 'B';
  if (score >= 60) return 'C+';
  if (score >= 50) return 'C';
  return 'D';
}

function normalizeTotal(technicalScore: number, processScore: number): number {
  return Math.round(((technicalScore + processScore) * 100) / 115);
}

function scoreAlphaCoveragePoints(minAlpha: number): number {
  if (minAlpha >= 0.15) return 25;
  if (minAlpha >= 0.10) return 20;
  if (minAlpha >= 0.05) return 15;
  if (minAlpha >= 0.02) return 10;
  return 0;
}

export function scoreManifestQuality(
  manifest: AssetManifest,
  gridMeta?: GridMeta,
  visualHeuristics: number = 15,
  /** Min alpha from inspect re-measurement; overrides stale manifest.quality.minAlphaCoverage */
  inspectedMinAlpha?: number,
): QualityBreakdown {
  let seamDetection = 0;
  const detector = gridMeta?.detector ?? manifest.quality?.gridDetector ?? manifest.gridDetector;
  if (detector === 'magenta') seamDetection = 25;
  else if (detector === 'weak-magenta') seamDetection = 12;
  else if (detector === 'profile') seamDetection = 8;
  else seamDetection = 0;

  const manifestMinAlpha = manifest.quality?.minAlphaCoverage ?? Math.min(
    ...manifest.items.map((i) => i.alphaCoverage ?? 0),
  );
  const minAlpha = inspectedMinAlpha ?? manifestMinAlpha;
  const alphaCoverage = scoreAlphaCoveragePoints(minAlpha);

  const minW = Math.min(...manifest.items.map((i) => i.width));
  const minH = Math.min(...manifest.items.map((i) => i.height));
  const minDim = Math.min(minW, minH);
  let dimensions = 0;
  if (minDim >= 128) dimensions = 25;
  else if (minDim >= 64) dimensions = 18;
  else if (minDim >= 32) dimensions = 12;
  else dimensions = 0;

  let metadata = 0;
  if (manifest.confirmToken) metadata += 5;
  if (manifest.cellSpecs?.every((c) => c.id)) metadata += 5;
  if (manifest.quality?.cellsPassed === manifest.items.length) metadata += 5;
  if (manifest.preset === 'logo' || manifest.preset === 'wordmark') metadata += 5;
  if (manifest.outputFormat) metadata += 2;
  metadata = Math.min(metadata, 25);

  const processScore = metadata;
  const technicalScore = seamDetection + alphaCoverage + dimensions + visualHeuristics;
  const total = normalizeTotal(technicalScore, processScore);
  return {
    seamDetection,
    alphaCoverage,
    dimensions,
    visualHeuristics,
    metadata,
    technicalScore,
    processScore,
    total,
    grade: gradeFromScore(total),
  };
}

async function measureBandAlphaFromTransparentSheet(
  transparentPath: string,
  band: GridBand,
): Promise<number | null> {
  if (!fs.existsSync(transparentPath)) return null;
  try {
    const cellBuffer = await sharp(transparentPath)
      .extract({ left: band.left, top: band.top, width: band.width, height: band.height })
      .png()
      .toBuffer();
    return await measureAlphaCoverage(cellBuffer);
  } catch {
    return null;
  }
}

export async function inspectBatch(outDir: string, options: InspectOptions = {}): Promise<InspectResult> {
  const resolved = path.resolve(outDir);
  const findings: InspectFinding[] = [];
  const minAlpha = options.minAlpha ?? 0.02;
  const minDimension = options.minDimension ?? 32;

  const manifestPath = path.join(resolved, 'manifest.json');
  if (!fs.existsSync(manifestPath)) {
    findings.push({ level: 'error', message: `manifest.json not found in ${resolved}` });
    return {
      ok: false,
      outDir: resolved,
      findings,
      breakdown: { seamDetection: 0, alphaCoverage: 0, dimensions: 0, visualHeuristics: 0, metadata: 0, technicalScore: 0, processScore: 0, total: 0, grade: 'D' },
    };
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8')) as AssetManifest;
  const batchOutputFormat: OutputFormat | undefined = manifest.outputFormat;

  if (batchOutputFormat === 'jpeg') {
    findings.push({
      level: 'info',
      message: 'JPEG batch: alpha gate requires sheet.transparent.png + sheet.grid.json bands (manifest alphaCoverage is not used)',
    });
  }

  const transparentSheetPath =
    manifest.files?.transparent && fs.existsSync(manifest.files.transparent)
      ? manifest.files.transparent
      : path.join(resolved, 'sheet.transparent.png');

  let gridMeta: GridMeta | undefined;
  const gridPath = path.join(resolved, 'sheet.grid.json');
  if (fs.existsSync(gridPath)) {
    gridMeta = JSON.parse(fs.readFileSync(gridPath, 'utf-8')) as GridMeta;
  }

  if (manifest.items.length === 0) {
    findings.push({ level: 'error', message: 'manifest has zero items' });
  }

  const manifestFilenames = new Set(manifest.items.map((i) => i.filename));
  try {
    const entries = fs.readdirSync(resolved);
    for (const name of entries) {
      if (!/^\d{2}_.+\.(webp|png|jpe?g)$/i.test(name)) continue;
      if (!manifestFilenames.has(name)) {
        findings.push({
          level: 'warn',
          message: `Orphan cell file not in manifest: ${name} (stale format switch or partial overwrite)`,
        });
      }
    }
  } catch {
    // unreadable outDir — other errors will surface
  }

  const visualIssues: { level: 'error' | 'warn' }[] = [];
  const measuredAlphas: number[] = [];

  for (const item of manifest.items) {
    if (!fs.existsSync(item.path)) {
      const fallback = path.join(resolved, item.filename);
      if (!fs.existsSync(fallback)) {
        findings.push({ level: 'error', message: `Missing file: ${item.filename}` });
        continue;
      }
      item.path = fallback;
    }

    try {
      validateCellDimensions(item.width, item.height, item.label, item.index, minDimension);
    } catch (err) {
      findings.push({
        level: 'error',
        message: err instanceof Error ? err.message.split('\n')[0] : String(err),
      });
    }

    const buf = fs.readFileSync(item.path);
    const itemFormat: OutputFormat | null =
      batchOutputFormat ?? inferOutputFormatFromFilename(item.filename) ?? null;

    const fileMeta = await sharp(buf).metadata();
    if (itemFormat) {
      const expectedSharp = sharpFormatForOutput(itemFormat);
      if (fileMeta.format && fileMeta.format !== expectedSharp) {
        findings.push({
          level: 'error',
          message: `Cell ${item.index + 1} (${item.filename}): file format ${fileMeta.format} != manifest ${itemFormat}`,
        });
      }
      const extFormat = inferOutputFormatFromFilename(item.filename);
      if (extFormat && extFormat !== itemFormat) {
        findings.push({
          level: 'error',
          message: `Cell ${item.index + 1} (${item.filename}): extension implies ${extFormat} but batch format is ${itemFormat}`,
        });
      }
    }

    let measuredAlpha: number;
    if (itemFormat === 'jpeg') {
      const band = gridMeta?.bands.find((b) => b.index === item.index);
      if (!band) {
        findings.push({
          level: 'error',
          message: `Cell ${item.index + 1} (${item.filename}): JPEG alpha gate requires sheet.grid.json band for index ${item.index}`,
        });
        measuredAlpha = 0;
      } else if (!fs.existsSync(transparentSheetPath)) {
        findings.push({
          level: 'error',
          message: `Cell ${item.index + 1} (${item.filename}): JPEG alpha gate requires sheet.transparent.png`,
        });
        measuredAlpha = 0;
      } else {
        const sheetAlpha = await measureBandAlphaFromTransparentSheet(transparentSheetPath, band);
        if (sheetAlpha == null) {
          findings.push({
            level: 'error',
            message: `Cell ${item.index + 1} (${item.filename}): failed to measure alpha from sheet.transparent.png band`,
          });
          measuredAlpha = 0;
        } else {
          measuredAlpha = sheetAlpha;
        }
      }
    } else {
      measuredAlpha = await measureAlphaCoverage(buf);
    }

    measuredAlphas.push(measuredAlpha);

    const preset = manifest.preset;

    if (!options.allowEmptyCells && measuredAlpha < minAlpha) {
      findings.push({
        level: 'error',
        message: `Cell ${item.index + 1} (${item.label}): ${(measuredAlpha * 100).toFixed(1)}% source alpha (min ${(minAlpha * 100).toFixed(0)}%)`,
      });
    } else if (
      (preset === 'logo' || preset === 'wordmark') &&
      measuredAlpha < 0.10 &&
      measuredAlpha >= minAlpha
    ) {
      findings.push({
        level: 'warn',
        message: `Cell ${item.index + 1} (${item.filename}): low ink fill ${(measuredAlpha * 100).toFixed(1)}% for ${preset} — re-prompt with bold opaque letterforms`,
      });
      visualIssues.push({ level: 'warn' });
    }

    const visuals = await measureCellVisuals(buf);
    const logoMinMaxSide = 120;

    if (visuals.magentaBorderRatio > 0.03) {
      const msg = `Cell ${item.index + 1} (${item.filename}): magenta seam residue ${(visuals.magentaBorderRatio * 100).toFixed(1)}% on border`;
      findings.push({ level: 'warn', message: msg });
      visualIssues.push({ level: 'warn' });
    }

    if (visuals.aspectRatio > 12) {
      findings.push({
        level: 'warn',
        message: `Cell ${item.index + 1} (${item.filename}): extreme aspect ${visuals.aspectRatio.toFixed(1)}:1 — possible strip/fragment`,
      });
      visualIssues.push({ level: 'warn' });
    }

    if ((preset === 'logo' || preset === 'wordmark') && visuals.maxSide < logoMinMaxSide) {
      findings.push({
        level: 'error',
        message: `Cell ${item.index + 1} (${item.filename}): max side ${visuals.maxSide}px < ${logoMinMaxSide} — fragment crop`,
      });
      visualIssues.push({ level: 'error' });
    }

    if (preset === 'wordmark' && visuals.maxSide < visuals.minSide * 1.2) {
      findings.push({
        level: 'warn',
        message: `Cell ${item.index + 1} (${item.filename}): not landscape (${item.width}x${item.height}) for wordmark preset`,
      });
      visualIssues.push({ level: 'warn' });
    }
  }

  const detector = gridMeta?.detector ?? manifest.quality?.gridDetector ?? manifest.gridDetector;
  if (manifest.mode === 'grid' && detector) {
    if (detector === 'magenta') {
      findings.push({ level: 'info', message: `Seam detector: magenta (${gridMeta?.magentaSeamHits ?? '?'}/${gridMeta?.totalSeams ?? '?'} hits)` });
    } else if (detector === 'weak-magenta') {
      const msg = 'Seam detector: weak-magenta — cell boundaries may be inaccurate';
      findings.push({ level: options.allowWeakSeams ? 'warn' : 'error', message: msg });
    } else {
      findings.push({
        level: options.allowWeakSeams ? 'warn' : 'error',
        message: `Seam detector: ${detector} — geometry fallback, re-generate with --mq high`,
      });
    }
  }

  const visualHeuristics = scoreVisualHeuristics(visualIssues);
  const inspectedMinAlpha = measuredAlphas.length > 0 ? Math.min(...measuredAlphas) : undefined;
  const breakdown = scoreManifestQuality(manifest, gridMeta, visualHeuristics, inspectedMinAlpha);
  const hasErrors = findings.some((f) => f.level === 'error');

  return {
    ok: !hasErrors,
    outDir: resolved,
    manifest,
    gridMeta,
    findings,
    breakdown,
  };
}

export function formatInspectReport(result: InspectResult): string {
  const lines: string[] = [];
  lines.push(`\x1b[1mBatch Inspection: ${result.outDir}\x1b[0m`);
  lines.push(`\x1b[36mQuality Score: ${result.breakdown.total}/100 (${result.breakdown.grade})\x1b[0m`);
  lines.push(`  technical: ${result.breakdown.technicalScore}/90  process: ${result.breakdown.processScore}/25`);
  lines.push(`  seam: ${result.breakdown.seamDetection}/25  alpha: ${result.breakdown.alphaCoverage}/25  dims: ${result.breakdown.dimensions}/25  visual: ${result.breakdown.visualHeuristics}/15  meta: ${result.breakdown.metadata}/25`);

  for (const f of result.findings) {
    const color = f.level === 'error' ? '\x1b[31m' : f.level === 'warn' ? '\x1b[33m' : '\x1b[90m';
    const tag = f.level.toUpperCase();
    lines.push(`${color}[${tag}] ${f.message}\x1b[0m`);
  }

  if (result.ok) {
    lines.push('\x1b[32m✓ PASS — batch meets automated quality gates\x1b[0m');
  } else {
    lines.push('\x1b[31m✗ FAIL — fix errors above or re-generate\x1b[0m');
    lines.push('  Retry: --mq high --preset logo --no-rembg --tight (for blue/cyan logos)');
  }

  return lines.join('\n');
}
