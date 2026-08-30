import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { detectGridSeams } from '../src/grid-detect.js';
import { clearSeamCorridors, extractAndSaveAssets } from '../src/pack.js';
import type { GeneratorOptions, OutputFormat } from '../src/types.js';

async function buildSyntheticSheet(): Promise<{ buffer: Buffer; outDir: string; gridMeta: Awaited<ReturnType<typeof detectGridSeams>> }> {
  const outDir = path.resolve(process.cwd(), 'tests/fixtures/out/format-export');
  if (fs.existsSync(outDir)) fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const width = 512;
  const height = 512;
  const raw = Buffer.alloc(width * height * 4, 0);
  for (let i = 0; i < width * height; i++) {
    raw[i * 4] = 192;
    raw[i * 4 + 1] = 192;
    raw[i * 4 + 2] = 192;
    raw[i * 4 + 3] = 255;
  }
  for (let y = 100; y < 400; y++) {
    for (let x = 100; x < 400; x++) {
      const idx = (y * width + x) * 4;
      raw[idx] = 59;
      raw[idx + 1] = 130;
      raw[idx + 2] = 246;
      raw[idx + 3] = 255;
    }
  }
  // top-right quadrant
  for (let y = 80; y < 220; y++) {
    for (let x = 300; x < 440; x++) {
      const idx = (y * width + x) * 4;
      raw[idx] = 16;
      raw[idx + 1] = 185;
      raw[idx + 2] = 129;
      raw[idx + 3] = 255;
    }
  }
  // bottom-left quadrant
  for (let y = 300; y < 440; y++) {
    for (let x = 80; x < 220; x++) {
      const idx = (y * width + x) * 4;
      raw[idx] = 245;
      raw[idx + 1] = 158;
      raw[idx + 2] = 11;
      raw[idx + 3] = 255;
    }
  }
  // bottom-right quadrant
  for (let y = 300; y < 440; y++) {
    for (let x = 300; x < 440; x++) {
      const idx = (y * width + x) * 4;
      raw[idx] = 139;
      raw[idx + 1] = 92;
      raw[idx + 2] = 246;
      raw[idx + 3] = 255;
    }
  }
  for (let y = 0; y < height; y++) {
    for (let x = 254; x <= 258; x++) {
      const idx = (y * width + x) * 4;
      raw[idx] = 255;
      raw[idx + 1] = 0;
      raw[idx + 2] = 255;
      raw[idx + 3] = 255;
    }
  }
  for (let x = 0; x < width; x++) {
    for (let y = 254; y <= 258; y++) {
      const idx = (y * width + x) * 4;
      raw[idx] = 255;
      raw[idx + 1] = 0;
      raw[idx + 2] = 255;
      raw[idx + 3] = 255;
    }
  }

  const transparent = Buffer.from(raw);
  for (let i = 0; i < width * height; i++) {
    const r = transparent[i * 4];
    const g = transparent[i * 4 + 1];
    const b = transparent[i * 4 + 2];
    if ((r === 192 && g === 192 && b === 192) || (r === 255 && g === 0 && b === 255)) {
      transparent[i * 4 + 3] = 0;
    }
  }

  const transparentPath = path.join(outDir, 'sheet.transparent.png');
  await sharp(transparent, { raw: { width, height, channels: 4 } }).png().toFile(transparentPath);
  const gridMeta = await detectGridSeams(transparentPath, 2, 2);
  const cleared = await clearSeamCorridors(transparentPath, gridMeta);
  return { buffer: cleared, outDir, gridMeta };
}

describe('format export e2e', () => {
  for (const format of ['png', 'jpeg'] as OutputFormat[]) {
    test(`extractAndSaveAssets writes ${format} cells with manifest metadata`, async () => {
      const { buffer, outDir, gridMeta } = await buildSyntheticSheet();
      const subDir = path.join(outDir, format);
      fs.mkdirSync(subDir, { recursive: true });

      const options: GeneratorOptions = {
        countOrGrid: '4',
        prompt: 'Format test',
        pad: 10,
        format,
        quality: 80,
      };

      const manifest = await extractAndSaveAssets(
        buffer,
        gridMeta,
        subDir,
        options,
        ['A', 'B', 'C', 'D'],
        `fmt_${format}`,
      );

      assert.strictEqual(manifest.outputFormat, format);
      assert.strictEqual(manifest.encodingQuality, 80);
      if (format === 'jpeg') {
        assert.strictEqual(manifest.jpegBackground, '#ffffff');
      }

      const expectedSharpFormat = format === 'jpeg' ? 'jpeg' : format;
      for (const item of manifest.items) {
        const meta = await sharp(item.path).metadata();
        assert.strictEqual(meta.format, expectedSharpFormat);
      }
    });
  }
});
