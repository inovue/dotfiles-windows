import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import { inspectBatch, scoreManifestQuality } from '../src/inspect.js';
import type { AssetManifest, GridMeta } from '../src/types.js';

async function writeFixtureBatch(outDir: string): Promise<void> {
  fs.mkdirSync(outDir, { recursive: true });

  const webpPath = path.join(outDir, '01_test_cell.webp');
  await sharp({
    create: { width: 256, height: 256, channels: 4, background: { r: 59, g: 130, b: 246, alpha: 1 } },
  }).webp().toFile(webpPath);

  const gridMeta: GridMeta = {
    version: 1,
    cols: 2,
    rows: 2,
    srcSize: [1024, 1024],
    keyColor: '#C0C0C0',
    separatorColor: '#FF00FF',
    bands: [],
    colSeams: [512],
    rowSeams: [512],
    detector: 'magenta',
    seamConfidence: { col: [0.9], row: [0.9] },
    magentaSeamHits: 2,
    totalSeams: 2,
  };
  fs.writeFileSync(path.join(outDir, 'sheet.grid.json'), JSON.stringify(gridMeta, null, 2));

  const manifest: AssetManifest = {
    version: 1,
    batchId: 'inspect-fixture',
    createdAt: new Date().toISOString(),
    mode: 'grid',
    grid: '2x2',
    aspectRatio: '1:1',
    prompt: 'test',
    preset: 'logo',
    confirmToken: 'abc123def456',
    outputFormat: 'webp',
    cellSpecs: [{ id: 'test_cell', prompt: 'Test cell' }],
    quality: {
      gridDetector: 'magenta',
      alphaGateMin: 0.02,
      minAlphaCoverage: 0.45,
      minWidth: 256,
      minHeight: 256,
      dimensionGateMin: 32,
      cellsPassed: 1,
    },
    items: [{
      id: 'test_cell',
      cellId: 'test_cell',
      filename: '01_test_cell.webp',
      index: 0,
      row: 1,
      col: 1,
      label: 'Test cell',
      alphaCoverage: 0.45,
      width: 256,
      height: 256,
      path: webpPath,
      relativePath: '01_test_cell.webp',
      astroImportPath: '01_test_cell.webp',
    }],
    files: {},
  };
  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));
}

describe('batch inspect', () => {
  test('inspectBatch passes good fixture with score >= 75', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/inspect-good');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    await writeFixtureBatch(outDir);

    const result = await inspectBatch(outDir);
    assert.strictEqual(result.ok, true);
    assert.ok(result.breakdown.total >= 75, `score ${result.breakdown.total} < 75`);
    assert.ok(['B', 'B+', 'A'].includes(result.breakdown.grade));
  });

  test('inspectBatch fails on missing manifest', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/inspect-empty');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    fs.mkdirSync(outDir, { recursive: true });

    const result = await inspectBatch(outDir);
    assert.strictEqual(result.ok, false);
    assert.ok(result.findings.some((f) => f.level === 'error'));
  });

  test('inspectBatch fails JPEG batch when sheet band alpha below gate', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/inspect-jpeg-low-alpha');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    fs.mkdirSync(outDir, { recursive: true });

    const size = 128;
    const jpgPath = path.join(outDir, '01_empty.jpg');
    await sharp({
      create: { width: size, height: size, channels: 3, background: { r: 255, g: 255, b: 255 } },
    }).jpeg().toFile(jpgPath);

    const raw = Buffer.alloc(size * size * 4, 0);
    for (let i = 0; i < 50; i++) {
      raw[i * 4 + 3] = 255;
    }
    const transparentPath = path.join(outDir, 'sheet.transparent.png');
    await sharp(raw, { raw: { width: size, height: size, channels: 4 } }).png().toFile(transparentPath);

    const gridMeta: GridMeta = {
      version: 1,
      cols: 1,
      rows: 1,
      srcSize: [size, size],
      keyColor: '#C0C0C0',
      separatorColor: '#FF00FF',
      bands: [{ index: 0, row: 1, col: 1, left: 0, top: 0, width: size, height: size }],
      colSeams: [],
      rowSeams: [],
      detector: 'magenta',
      magentaSeamHits: 0,
      totalSeams: 0,
    };
    fs.writeFileSync(path.join(outDir, 'sheet.grid.json'), JSON.stringify(gridMeta, null, 2));

    const manifest: AssetManifest = {
      version: 1,
      batchId: 'jpeg-low',
      createdAt: new Date().toISOString(),
      mode: 'grid',
      grid: '1x1',
      aspectRatio: '1:1',
      prompt: 'test',
      outputFormat: 'jpeg',
      encodingQuality: 80,
      jpegBackground: '#ffffff',
      quality: { minAlphaCoverage: 0.9, alphaGateMin: 0.02, cellsPassed: 1 },
      items: [{
        id: 'empty',
        filename: '01_empty.jpg',
        index: 0,
        label: 'Empty cell',
        alphaCoverage: 0.9,
        width: size,
        height: size,
        path: jpgPath,
        relativePath: '01_empty.jpg',
        astroImportPath: '01_empty.jpg',
      }],
      files: { transparent: transparentPath },
    };
    fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

    const result = await inspectBatch(outDir);
    assert.strictEqual(result.ok, false);
    assert.ok(result.findings.some((f) => f.level === 'error' && f.message.includes('source alpha')));
    assert.ok(result.breakdown.alphaCoverage <= 10, 'score must use inspected sheet alpha, not stale manifest');
  });

  test('inspectBatch fails legacy JPEG without sheet artifacts', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/inspect-jpeg-legacy');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    fs.mkdirSync(outDir, { recursive: true });

    const jpgPath = path.join(outDir, '01_legacy.jpg');
    await sharp({
      create: { width: 64, height: 64, channels: 3, background: { r: 255, g: 255, b: 255 } },
    }).jpeg().toFile(jpgPath);

    const manifest: AssetManifest = {
      version: 1,
      batchId: 'legacy',
      createdAt: new Date().toISOString(),
      mode: 'grid',
      aspectRatio: '1:1',
      prompt: 'test',
      items: [{
        id: 'legacy',
        filename: '01_legacy.jpg',
        index: 0,
        label: 'Legacy',
        width: 64,
        height: 64,
        path: jpgPath,
        relativePath: '01_legacy.jpg',
        astroImportPath: '01_legacy.jpg',
      }],
      files: {},
    };
    fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

    const result = await inspectBatch(outDir);
    assert.strictEqual(result.ok, false);
    assert.ok(
      result.findings.some(
        (f) => f.level === 'error' &&
          (f.message.includes('sheet.transparent.png') || f.message.includes('sheet.grid.json')),
      ),
    );
  });

  test('inspectBatch fails when file bytes do not match outputFormat', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/inspect-format-mismatch');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    fs.mkdirSync(outDir, { recursive: true });

    const fakePngPath = path.join(outDir, '01_cell.png');
    await sharp({
      create: { width: 64, height: 64, channels: 4, background: { r: 10, g: 20, b: 30, alpha: 1 } },
    }).webp().toFile(fakePngPath);

    const manifest: AssetManifest = {
      version: 1,
      batchId: 'fmt',
      createdAt: new Date().toISOString(),
      mode: 'grid',
      aspectRatio: '1:1',
      prompt: 'test',
      outputFormat: 'png',
      items: [{
        id: 'cell',
        filename: '01_cell.png',
        index: 0,
        label: 'Cell',
        alphaCoverage: 0.5,
        width: 64,
        height: 64,
        path: fakePngPath,
        relativePath: '01_cell.png',
        astroImportPath: '01_cell.png',
      }],
      files: {},
    };
    fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

    const result = await inspectBatch(outDir);
    assert.strictEqual(result.ok, false);
    assert.ok(result.findings.some((f) => f.level === 'error' && f.message.includes('file format')));
  });

  test('inspectBatch warns on orphan cell files not in manifest', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/inspect-orphan');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    await writeFixtureBatch(outDir);

    const orphanPath = path.join(outDir, '02_stale.webp');
    await sharp({
      create: { width: 64, height: 64, channels: 4, background: { r: 200, g: 0, b: 0, alpha: 1 } },
    }).webp().toFile(orphanPath);

    const result = await inspectBatch(outDir);
    assert.ok(result.findings.some((f) => f.level === 'warn' && f.message.includes('Orphan cell file')));
  });

  test('scoreManifestQuality uses inspected min alpha over stale manifest', () => {
    const base: AssetManifest = {
      version: 1,
      batchId: 'x',
      createdAt: '',
      mode: 'grid',
      aspectRatio: '1:1',
      prompt: '',
      quality: { minAlphaCoverage: 0.45, alphaGateMin: 0.02, cellsPassed: 1 },
      items: [{
        id: 'a', filename: 'a.webp', index: 0, label: 'a',
        alphaCoverage: 0.45, width: 200, height: 200,
        path: '', relativePath: '', astroImportPath: '',
      }],
      files: {},
    };

    const stale = scoreManifestQuality(base, { detector: 'magenta' } as GridMeta);
    const inspected = scoreManifestQuality(base, { detector: 'magenta' } as GridMeta, 15, 0.01);
    assert.ok(stale.alphaCoverage > inspected.alphaCoverage);
    assert.strictEqual(inspected.alphaCoverage, 0);
  });

  test('scoreManifestQuality weights magenta seams highest', () => {
    const base: AssetManifest = {
      version: 1,
      batchId: 'x',
      createdAt: '',
      mode: 'grid',
      aspectRatio: '1:1',
      prompt: '',
      confirmToken: 'tok',
      preset: 'logo',
      cellSpecs: [{ id: 'a', prompt: 'a' }],
      items: [{
        id: 'a', filename: 'a.webp', index: 0, label: 'a',
        alphaCoverage: 0.2, width: 200, height: 200,
        path: '', relativePath: '', astroImportPath: '',
      }],
      files: {},
    };

    const magenta = scoreManifestQuality(base, { detector: 'magenta' } as GridMeta);
    const equal = scoreManifestQuality(base, { detector: 'equal-split' } as GridMeta);
    assert.ok(magenta.seamDetection > equal.seamDetection);
    assert.ok(magenta.total > equal.total);
  });
});
