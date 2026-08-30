import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { detectGridSeams } from '../src/grid-detect.js';
import { clearSeamCorridors, extractAndSaveAssets } from '../src/pack.js';
import { buildPrompt } from '../src/prompt.js';
import { validateGridSeams } from '../src/validate.js';
import type { GeneratorOptions } from '../src/types.js';

async function buildSyntheticSpriteSheet(outPath: string, width = 1024, height = 1024): Promise<void> {
  const channels = 4;
  const buffer = Buffer.alloc(width * height * channels);

  for (let i = 0; i < width * height; i++) {
    buffer[i * 4] = 192;
    buffer[i * 4 + 1] = 192;
    buffer[i * 4 + 2] = 192;
    buffer[i * 4 + 3] = 255;
  }

  function fillRect(x0: number, y0: number, w: number, h: number, r: number, g: number, b: number) {
    for (let y = y0; y < y0 + h && y < height; y++) {
      for (let x = x0; x < x0 + w && x < width; x++) {
        const idx = (y * width + x) * channels;
        buffer[idx] = r;
        buffer[idx + 1] = g;
        buffer[idx + 2] = b;
        buffer[idx + 3] = 255;
      }
    }
  }

  fillRect(80, 80, 360, 360, 59, 130, 246);
  fillRect(580, 100, 300, 320, 16, 185, 129);
  fillRect(100, 600, 340, 200, 245, 158, 11);
  fillRect(580, 580, 280, 280, 139, 92, 246);

  for (let y = 0; y < height; y++) {
    for (let x = 509; x <= 515; x++) {
      const idx = (y * width + x) * channels;
      buffer[idx] = 255;
      buffer[idx + 1] = 0;
      buffer[idx + 2] = 255;
      buffer[idx + 3] = 255;
    }
  }
  for (let x = 0; x < width; x++) {
    for (let y = 509; y <= 515; y++) {
      const idx = (y * width + x) * channels;
      buffer[idx] = 255;
      buffer[idx + 1] = 0;
      buffer[idx + 2] = 255;
      buffer[idx + 3] = 255;
    }
  }

  await sharp(buffer, { raw: { width, height, channels: 4 } }).png().toFile(outPath);
}

describe('realistic sprite sheet pipeline (repo-local fixture)', () => {
  test('2x2 grid: seam detect, chroma matting, extract, alpha gate', async () => {
    const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/synthetic_2x2');
    if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
    fs.mkdirSync(outDir, { recursive: true });

    const rawPath = path.join(outDir, 'sheet.raw.png');
    await buildSyntheticSpriteSheet(rawPath);

    const gridMeta = await detectGridSeams(rawPath, 2, 2);
    assert.strictEqual(gridMeta.detector, 'magenta');
    validateGridSeams(gridMeta);

    const { width, height } = await sharp(rawPath).metadata() as { width: number; height: number };
    const rawBuf = await sharp(rawPath).ensureAlpha().raw().toBuffer();
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = (y * width + x) * 4;
        const r = rawBuf[idx], g = rawBuf[idx + 1], b = rawBuf[idx + 2];
        const isMagenta = r > 180 && b > 180 && g < 120;
        const isGray = Math.abs(r - g) < 20 && Math.abs(g - b) < 20 && r > 150 && r < 225;
        if (isMagenta || isGray) rawBuf[idx + 3] = 0;
      }
    }
    const transparentPath = path.join(outDir, 'sheet.transparent.png');
    await sharp(rawBuf, { raw: { width, height, channels: 4 } }).png().toFile(transparentPath);

    const corridorCleared = await clearSeamCorridors(transparentPath, gridMeta);
    const itemsList = ['AI Assistant', 'Cloud Sync', 'Security', 'Analytics'];
    const gridOptions: GeneratorOptions = {
      countOrGrid: '4',
      prompt: 'AI SaaS Features',
      style: 'clay',
      pad: 10,
      format: 'webp',
      quality: 80,
    };

    const manifest = await extractAndSaveAssets(
      corridorCleared,
      gridMeta,
      outDir,
      gridOptions,
      itemsList,
      'synthetic_2x2',
      'test prompt',
      itemsList.map((prompt, i) => ({ id: ['ai', 'cloud', 'security', 'analytics'][i], prompt })),
    );

    assert.strictEqual(manifest.items.length, 4);
    for (const item of manifest.items) {
      assert.ok(fs.existsSync(item.path));
      assert.ok(item.alphaCoverage != null && item.alphaCoverage > 0.02);
      const meta = await sharp(item.path).metadata();
      assert.strictEqual(meta.format, 'webp');
      assert.strictEqual(meta.width, meta.height);
    }
  });

  test('prompt synthesis with reference mode', () => {
    const promptResult = buildPrompt({
      countOrGrid: '4',
      prompt: 'Mascot Action Set',
      style: 'clay',
      refImages: ['./mascot.png'],
      refMode: 'character',
      printPrompt: true,
      items: [
        'Mascot typing on keyboard',
        'Mascot with magnifying glass',
        'Mascot with security hardhat',
        'Mascot carrying golden key',
      ],
    });

    assert.strictEqual(promptResult.gridInfo.total, 4);
    assert.ok(promptResult.prompt.includes('Strictly maintain the exact character / mascot identity'));
    assert.ok(promptResult.confirmToken.length === 12);
  });
});
