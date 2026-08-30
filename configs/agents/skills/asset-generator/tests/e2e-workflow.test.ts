import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { detectGridSeams } from '../src/grid-detect.js';
import { clearSeamCorridors, extractAndSaveAssets } from '../src/pack.js';
import type { GeneratorOptions } from '../src/types.js';

describe('e2e asset generator pipeline with synthetic 2x2 grid image', () => {
  test('end-to-end detection, corridor clearing, smart normalization, and webp export', async () => {
    const outDir = path.resolve(process.cwd(), 'src/assets/images/generated/test_sample_batch');
    if (fs.existsSync(outDir)) {
      fs.rmSync(outDir, { recursive: true, force: true });
    }
    fs.mkdirSync(outDir, { recursive: true });

    const width = 1024;
    const height = 1024;
    const rawChannels = 4;
    const buffer = Buffer.alloc(width * height * rawChannels);

    // 1. Fill background with Neutral Gray #C0C0C0 (192, 192, 192, 255)
    for (let i = 0; i < width * height; i++) {
      buffer[i * 4] = 192;     // R
      buffer[i * 4 + 1] = 192; // G
      buffer[i * 4 + 2] = 192; // B
      buffer[i * 4 + 3] = 255; // Alpha
    }

    // Helper: Draw filled rectangle
    function drawRect(x0: number, y0: number, w: number, h: number, r: number, g: number, b: number) {
      for (let y = y0; y < y0 + h && y < height; y++) {
        for (let x = x0; x < x0 + w && x < width; x++) {
          const idx = (y * width + x) * rawChannels;
          buffer[idx] = r;
          buffer[idx + 1] = g;
          buffer[idx + 2] = b;
          buffer[idx + 3] = 255;
        }
      }
    }

    // Helper: Draw filled circle
    function drawCircle(cx: number, cy: number, radius: number, r: number, g: number, b: number) {
      for (let y = cy - radius; y <= cy + radius; y++) {
        for (let x = cx - radius; x <= cx + radius; x++) {
          if (x >= 0 && x < width && y >= 0 && y < height) {
            const dist = Math.sqrt((x - cx) ** 2 + (y - cy) ** 2);
            if (dist <= radius) {
              const idx = (y * width + x) * rawChannels;
              buffer[idx] = r;
              buffer[idx + 1] = g;
              buffer[idx + 2] = b;
              buffer[idx + 3] = 255;
            }
          }
        }
      }
    }

    // 2. Draw 4 distinct mock objects in the 4 quadrants (2x2)
    // Quadrant 1 (Top-Left): Blue Circle (AI Assistant Bubble)
    drawCircle(256, 256, 120, 59, 130, 246);

    // Quadrant 2 (Top-Right): Green Vertical Rectangle (Cloud Sync Server)
    drawRect(680, 160, 150, 280, 16, 185, 129);

    // Quadrant 3 (Bottom-Left): Amber Horizontal Capsule (Security Shield)
    drawRect(140, 720, 280, 140, 245, 158, 11);

    // Quadrant 4 (Bottom-Right): Purple Diamond/Square (Analytics Chart)
    drawRect(680, 680, 200, 200, 139, 92, 246);

    // 3. Draw Magenta #FF00FF Seam Lines (x=512, y=512, width 6px)
    for (let y = 0; y < height; y++) {
      for (let x = 509; x <= 515; x++) {
        const idx = (y * width + x) * rawChannels;
        buffer[idx] = 255;     // R
        buffer[idx + 1] = 0;   // G
        buffer[idx + 2] = 255; // B
      }
    }
    for (let x = 0; x < width; x++) {
      for (let y = 509; y <= 515; y++) {
        const idx = (y * width + x) * rawChannels;
        buffer[idx] = 255;     // R
        buffer[idx + 1] = 0;   // G
        buffer[idx + 2] = 255; // B
      }
    }

    const rawPath = path.join(outDir, 'sheet.raw.png');
    await sharp(buffer, { raw: { width, height, channels: 4 } }).png().toFile(rawPath);

    // 4. Test Seam Detection
    const gridMeta = await detectGridSeams(rawPath, 2, 2);
    const gridMetaPath = path.join(outDir, 'sheet.grid.json');
    fs.writeFileSync(gridMetaPath, JSON.stringify(gridMeta, null, 2));

    assert.strictEqual(gridMeta.cols, 2);
    assert.strictEqual(gridMeta.rows, 2);
    assert.strictEqual(gridMeta.bands.length, 4);
    assert.ok(Math.abs(gridMeta.colSeams[0] - 512) <= 5);
    assert.ok(Math.abs(gridMeta.rowSeams[0] - 512) <= 5);

    // 5. Simulate Background Removal (Gray and Magenta -> Transparent)
    const transparentBuffer = Buffer.from(buffer);
    for (let i = 0; i < width * height; i++) {
      const r = transparentBuffer[i * 4];
      const g = transparentBuffer[i * 4 + 1];
      const b = transparentBuffer[i * 4 + 2];
      if ((r === 192 && g === 192 && b === 192) || (r === 255 && g === 0 && b === 255)) {
        transparentBuffer[i * 4 + 3] = 0;
      }
    }
    const transparentPath = path.join(outDir, 'sheet.transparent.png');
    await sharp(transparentBuffer, { raw: { width, height, channels: 4 } }).png().toFile(transparentPath);

    // 6. Clear Seam Corridors
    const corridorClearedBuffer = await clearSeamCorridors(transparentPath, gridMeta);

    // 7. Extract, Normalize & Pack Assets
    const itemsList = [
      'AI Assistant Bubble (Circle)',
      'Cloud Sync Server (Tall Rectangle)',
      'Security Shield (Wide Capsule)',
      'Analytics Chart (Square)',
    ];

    const options: GeneratorOptions = {
      countOrGrid: '4',
      prompt: 'SaaS Feature Icons',
      style: 'clay',
      pad: 10,
      format: 'webp',
      quality: 80,
    };

    const manifest = await extractAndSaveAssets(
      corridorClearedBuffer,
      gridMeta,
      outDir,
      options,
      itemsList,
      'test_sample_batch'
    );

    assert.strictEqual(manifest.items.length, 4);

    // 8. Validate extracted files
    for (const item of manifest.items) {
      assert.ok(fs.existsSync(item.path));
      const meta = await sharp(item.path).metadata();
      assert.strictEqual(meta.format, 'webp');
      assert.strictEqual(meta.width, meta.height); // Must be a perfect square
      assert.strictEqual(meta.channels, 4);        // Must have alpha channel
    }

    // 9. Validate manifest.json
    const manifestOnDisk = JSON.parse(fs.readFileSync(path.join(outDir, 'manifest.json'), 'utf-8'));
    assert.strictEqual(manifestOnDisk.items.length, 4);
    assert.strictEqual(manifestOnDisk.mode, 'grid');
  });
});
