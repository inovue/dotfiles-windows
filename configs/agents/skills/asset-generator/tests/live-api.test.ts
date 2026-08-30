import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { requireFalKey } from '../src/fal.js';
import { runLiveBatch, summarizeStability } from './live-helpers.js';

const LIVE = process.env.ASSET_GENERATOR_LIVE_TEST === '1';
const FILTER = process.env.ASSET_GENERATOR_LIVE_FILTER?.split(',').map((s) => s.trim()) ?? null;
const MIN_TOTAL = Number(process.env.ASSET_GENERATOR_MIN_SCORE ?? '70');
const MIN_TECHNICAL = Number(process.env.ASSET_GENERATOR_MIN_TECHNICAL ?? '65');
const MAX_TECHNICAL_SPREAD = Number(process.env.ASSET_GENERATOR_MAX_SPREAD ?? '20');
const STABILITY_RUNS = Number(process.env.ASSET_GENERATOR_STABILITY_RUNS ?? '3');
const LOGO_STABILITY_RUNS = Number(process.env.ASSET_GENERATOR_LOGO_STABILITY_RUNS ?? '3');

function shouldRun(name: string): boolean {
  return !FILTER || FILTER.includes(name);
}

const logoBatch = {
  countOrGrid: '4',
  prompt: 'Financial Fantasy Brand Logos',
  style: 'flat',
  preset: 'logo' as const,
  itemsRaw: 'tests/fixtures/cells-live-logos.json',
  modelQuality: 'high' as const,
  rembg: false,
  tight: true,
  format: 'webp' as const,
  quality: 85,
};

describe('live fal.ai grid pipeline (optional)', { skip: !LIVE }, () => {
  test('2x2 flat icons: generate, pack, inspect (strict seams)', { timeout: 300_000, skip: !shouldRun('icons') }, async () => {
    requireFalKey();

    const { inspection } = await runLiveBatch({
      countOrGrid: '4',
      prompt: 'SaaS Feature Icons',
      style: 'flat',
      preset: 'icon',
      itemsRaw: 'tests/fixtures/cells-live.json',
      modelQuality: 'medium',
      format: 'webp',
      quality: 80,
      outDir: path.resolve(process.cwd(), 'tests/fixtures/out/live-api'),
    });

    assert.strictEqual(inspection.manifest?.items.length, 4);
    assert.strictEqual(inspection.manifest?.outputFormat, 'webp');
    assert.ok(inspection.ok, inspection.findings.filter((f) => f.level === 'error').map((f) => f.message).join('; '));
    assert.ok(inspection.breakdown.technicalScore >= MIN_TECHNICAL);
    assert.ok(inspection.breakdown.total >= MIN_TOTAL);
  });

  test('2x2 flat icons: png output format smoke', { timeout: 300_000, skip: !shouldRun('png-icons') }, async () => {
    requireFalKey();

    const { inspection } = await runLiveBatch({
      countOrGrid: '4',
      prompt: 'SaaS Feature Icons PNG',
      style: 'flat',
      preset: 'icon',
      itemsRaw: 'tests/fixtures/cells-live.json',
      modelQuality: 'medium',
      format: 'png',
      quality: 80,
      outDir: path.resolve(process.cwd(), 'tests/fixtures/out/live-api-png'),
    });

    assert.strictEqual(inspection.manifest?.items.length, 4);
    assert.strictEqual(inspection.manifest?.outputFormat, 'png');
    assert.ok(inspection.ok, inspection.findings.filter((f) => f.level === 'error').map((f) => f.message).join('; '));
    assert.ok(inspection.breakdown.technicalScore >= MIN_TECHNICAL);
    console.log(`[PNG LIVE] technical=${inspection.breakdown.technicalScore}/90 total=${inspection.breakdown.total}/100`);
  });

  test('2x2 logos: --preset logo --no-rembg --tight (strict seams)', { timeout: 300_000, skip: !shouldRun('logos') }, async () => {
    requireFalKey();

    const { inspection } = await runLiveBatch({
      ...logoBatch,
      outDir: path.resolve(process.cwd(), 'tests/fixtures/out/live-logos'),
    });

    assert.strictEqual(inspection.manifest?.items.length, 4);
    assert.strictEqual(inspection.manifest?.outputFormat, 'webp');
    assert.ok(inspection.ok, inspection.findings.filter((f) => f.level === 'error').map((f) => f.message).join('; '));
    assert.ok(inspection.breakdown.technicalScore >= Number(process.env.ASSET_GENERATOR_LOGO_MIN_TECHNICAL ?? '60'));

    console.log(`[LOGO LIVE] technical=${inspection.breakdown.technicalScore}/90 total=${inspection.breakdown.total}/100 visual=${inspection.breakdown.visualHeuristics}/15`);
    console.log('[LOGO LIVE] Manual: 128px width — FINANCIAL/FANTASY full text, no CIAL fragments');
  });

  test('2x2 logos: png output format smoke', { timeout: 300_000, skip: !shouldRun('png-logos') }, async () => {
    requireFalKey();

    const { inspection } = await runLiveBatch({
      ...logoBatch,
      format: 'png',
      outDir: path.resolve(process.cwd(), 'tests/fixtures/out/live-logos-png'),
    });

    assert.strictEqual(inspection.manifest?.items.length, 4);
    assert.strictEqual(inspection.manifest?.outputFormat, 'png');
    assert.ok(inspection.ok, inspection.findings.filter((f) => f.level === 'error').map((f) => f.message).join('; '));
    assert.ok(inspection.breakdown.technicalScore >= Number(process.env.ASSET_GENERATOR_LOGO_MIN_TECHNICAL ?? '60'));
    console.log(`[PNG LOGO LIVE] technical=${inspection.breakdown.technicalScore}/90 total=${inspection.breakdown.total}/100`);
  });

  test('4x2 wordmarks: --preset wordmark --no-rembg --tight', { timeout: 360_000, skip: !shouldRun('wordmarks') }, async () => {
    requireFalKey();

    const { inspection } = await runLiveBatch({
      countOrGrid: '4x2',
      prompt: 'Financial Fantasy Brand Wordmarks',
      style: 'flat',
      preset: 'wordmark',
      itemsRaw: 'tests/fixtures/cells-live-wordmarks-8.json',
      modelQuality: 'high',
      rembg: false,
      tight: true,
      format: 'webp',
      quality: 85,
      outDir: path.resolve(process.cwd(), 'tests/fixtures/out/live-wordmarks'),
    });

    assert.strictEqual(inspection.manifest?.items.length, 8);
    assert.ok(inspection.ok, inspection.findings.filter((f) => f.level === 'error').map((f) => f.message).join('; '));
    assert.ok(inspection.breakdown.technicalScore >= Number(process.env.ASSET_GENERATOR_WORDMARK_MIN_TECHNICAL ?? '58'));

    const landscapeCount = inspection.manifest!.items.filter((i) => i.width > i.height * 1.1).length;
    console.log(`[WORDMARK LIVE] technical=${inspection.breakdown.technicalScore}/90 total=${inspection.breakdown.total}/100 landscape=${landscapeCount}/8`);
  });

  test('3x3 flat icons: generate, pack, inspect (strict seams)', { timeout: 360_000, skip: !shouldRun('icons-3x3') }, async () => {
    requireFalKey();

    const { inspection } = await runLiveBatch({
      countOrGrid: '9',
      prompt: 'SaaS Feature Icon Set',
      style: 'flat',
      preset: 'icon',
      itemsRaw: 'tests/fixtures/cells-live-9.json',
      modelQuality: 'medium',
      format: 'webp',
      quality: 80,
      outDir: path.resolve(process.cwd(), 'tests/fixtures/out/live-3x3'),
    });

    assert.strictEqual(inspection.manifest?.items.length, 9);
    assert.ok(inspection.ok, inspection.findings.filter((f) => f.level === 'error').map((f) => f.message).join('; '));
    assert.ok(inspection.breakdown.technicalScore >= Number(process.env.ASSET_GENERATOR_3X3_MIN_TECHNICAL ?? '58'));
    console.log(`[3x3 LIVE] technical=${inspection.breakdown.technicalScore}/90 detector=${inspection.gridMeta?.detector}`);
  });

  test('stability: N consecutive identical icon batches', { timeout: 900_000, skip: !shouldRun('stability-icons') }, async () => {
    requireFalKey();

    const baseDir = path.resolve(process.cwd(), 'tests/fixtures/out/live-stability');
    const inspections = [];

    for (let i = 0; i < STABILITY_RUNS; i++) {
      const { inspection } = await runLiveBatch({
        countOrGrid: '4',
        prompt: 'SaaS Feature Icons',
        style: 'flat',
        preset: 'icon',
        itemsRaw: 'tests/fixtures/cells-live.json',
        modelQuality: 'medium',
        format: 'webp',
        quality: 80,
        outDir: path.join(baseDir, `run-${i + 1}`),
      });
      inspections.push(inspection);
    }

    const stats = summarizeStability(inspections);
    console.log(`[STABILITY icons] technical=${stats.technicalScores.join(',')} spread=${stats.spread}`);

    assert.ok(stats.spread <= MAX_TECHNICAL_SPREAD);
    assert.ok(stats.detectors.filter((d) => d === 'magenta').length >= Math.ceil(STABILITY_RUNS / 2));
  });

  test('stability: N consecutive logo batches', { timeout: 900_000, skip: !shouldRun('stability-logos') }, async () => {
    requireFalKey();

    const baseDir = path.resolve(process.cwd(), 'tests/fixtures/out/live-stability-logos');
    const inspections = [];

    for (let i = 0; i < LOGO_STABILITY_RUNS; i++) {
      const { inspection } = await runLiveBatch({
        ...logoBatch,
        outDir: path.join(baseDir, `run-${i + 1}`),
      });
      inspections.push(inspection);
    }

    const stats = summarizeStability(inspections);
    console.log(`[STABILITY logos] technical=${stats.technicalScores.join(',')} spread=${stats.spread}`);

    for (const insp of inspections) {
      assert.ok(insp.ok, 'logo stability run inspect failed');
    }

    assert.ok(stats.spread <= MAX_TECHNICAL_SPREAD + 5, `logo spread ${stats.spread} too high`);
  });
});
