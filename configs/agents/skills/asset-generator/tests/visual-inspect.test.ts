import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { measureBorderMagentaRatio, measureCellVisuals, scoreVisualHeuristics } from '../src/visual-inspect.js';

describe('visual inspect heuristics', () => {
  test('measureBorderMagentaRatio detects magenta border pixels', async () => {
    const w = 100;
    const h = 100;
    const raw = Buffer.alloc(w * h * 4, 0);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        const onBorder = x === 0 || y === 0 || x === w - 1 || y === h - 1;
        if (onBorder) {
          raw[i] = 255;
          raw[i + 1] = 0;
          raw[i + 2] = 255;
          raw[i + 3] = 255;
        } else {
          raw[i + 3] = 0;
        }
      }
    }
    const png = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
    const ratio = await measureBorderMagentaRatio(png);
    assert.ok(ratio > 0.5);
  });

  test('scoreVisualHeuristics deducts for warnings and errors', () => {
    assert.strictEqual(scoreVisualHeuristics([]), 15);
    assert.strictEqual(scoreVisualHeuristics([{ level: 'warn' }]), 12);
    assert.strictEqual(scoreVisualHeuristics([{ level: 'error' }]), 7);
  });

  test('measureCellVisuals reports aspect ratio', async () => {
    const buf = await sharp({
      create: { width: 400, height: 100, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
    }).png().toBuffer();
    const m = await measureCellVisuals(buf);
    assert.strictEqual(m.aspectRatio, 4);
    assert.strictEqual(m.maxSide, 400);
  });
});
