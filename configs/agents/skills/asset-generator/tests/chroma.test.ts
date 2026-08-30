import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {
  applyChromaKeyInPlace,
  getLargestOpaqueBBox,
  isChromaOrSeparator,
} from '../src/chroma.js';
import { tightCropCell } from '../src/pack.js';

describe('chroma key & largest-component bbox', () => {
  test('isChromaOrSeparator detects gray and magenta', () => {
    assert.ok(isChromaOrSeparator(192, 192, 192));
    assert.ok(isChromaOrSeparator(255, 0, 255));
    assert.ok(!isChromaOrSeparator(50, 100, 200));
  });

  test('getLargestOpaqueBBox picks main blob over small fragment', () => {
    const w = 200;
    const h = 200;
    const raw = Buffer.alloc(w * h * 4);

    // Large subject block (rows 40-160, cols 30-170)
    for (let y = 40; y < 160; y++) {
      for (let x = 30; x < 170; x++) {
        const i = (y * w + x) * 4;
        raw[i] = 100;
        raw[i + 1] = 150;
        raw[i + 2] = 255;
        raw[i + 3] = 255;
      }
    }

    // Small bright fragment (noise that old bbox would sometimes prefer)
    for (let y = 5; y < 15; y++) {
      for (let x = 5; x < 15; x++) {
        const i = (y * w + x) * 4;
        raw[i] = 255;
        raw[i + 1] = 255;
        raw[i + 2] = 255;
        raw[i + 3] = 255;
      }
    }

    const bbox = getLargestOpaqueBBox(raw, w, h, 15);
    assert.ok(bbox);
    assert.ok(bbox!.width > 100);
    assert.ok(bbox!.height > 100);
    assert.strictEqual(bbox!.left, 30);
    assert.strictEqual(bbox!.top, 40);
  });

  test('applyChromaKeyInPlace clears gray background', () => {
    const w = 50;
    const h = 50;
    const raw = Buffer.alloc(w * h * 4, 0);
    for (let i = 0; i < w * h; i++) {
      raw[i * 4] = 192;
      raw[i * 4 + 1] = 192;
      raw[i * 4 + 2] = 192;
      raw[i * 4 + 3] = 255;
    }
    raw[25 * 4 + 3] = 255; // center pixel stays subject
    raw[25 * 4] = 10;
    raw[25 * 4 + 1] = 20;
    raw[25 * 4 + 2] = 200;

    applyChromaKeyInPlace(raw, w, h);
    assert.strictEqual(raw[0 * 4 + 3], 0);
    assert.ok(raw[25 * 4 + 3] > 0);
  });

  test('tightCropCell removes chroma background and crops to main subject', async () => {
    const w = 256;
    const h = 256;
    const raw = Buffer.alloc(w * h * 4);

    for (let i = 0; i < w * h; i++) {
      raw[i * 4] = 192;
      raw[i * 4 + 1] = 192;
      raw[i * 4 + 2] = 192;
      raw[i * 4 + 3] = 255;
    }

    for (let y = 80; y < 180; y++) {
      for (let x = 40; x < 220; x++) {
        const i = (y * w + x) * 4;
        raw[i] = 255;
        raw[i + 1] = 255;
        raw[i + 2] = 255;
        raw[i + 3] = 200;
      }
    }

    const png = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
    const cropped = await tightCropCell(png);
    const meta = await sharp(cropped).metadata();

    assert.ok(meta.width! < w);
    assert.ok(meta.height! < h);
    assert.ok(meta.width! > 100);
  });

  test('tightCropCell keeps full cell when bbox is tiny fragment', async () => {
    const w = 256;
    const h = 256;
    const raw = Buffer.alloc(w * h * 4);

    for (let i = 0; i < w * h; i++) {
      raw[i * 4] = 192;
      raw[i * 4 + 1] = 192;
      raw[i * 4 + 2] = 192;
      raw[i * 4 + 3] = 255;
    }

    for (let y = 10; y < 30; y++) {
      for (let x = 10; x < 30; x++) {
        const i = (y * w + x) * 4;
        raw[i] = 10;
        raw[i + 1] = 10;
        raw[i + 2] = 10;
        raw[i + 3] = 255;
      }
    }

    const png = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
    const cropped = await tightCropCell(png, { minMaxSideRatio: 0.25 });
    const meta = await sharp(cropped).metadata();

    assert.strictEqual(meta.width, w);
    assert.strictEqual(meta.height, h);
  });

  test('tightCropCell keeps full cell when bbox is thin horizontal strip', async () => {
    const w = 256;
    const h = 128;
    const raw = Buffer.alloc(w * h * 4, 0);

    for (let i = 0; i < w * h; i++) {
      raw[i * 4] = 192;
      raw[i * 4 + 1] = 192;
      raw[i * 4 + 2] = 192;
      raw[i * 4 + 3] = 255;
    }

    for (let y = 60; y < 65; y++) {
      for (let x = 20; x < 230; x++) {
        const i = (y * w + x) * 4;
        raw[i] = 20;
        raw[i + 1] = 20;
        raw[i + 2] = 20;
        raw[i + 3] = 255;
      }
    }

    const png = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
    const cropped = await tightCropCell(png, { minMaxSideRatio: 0.25, minCropMinSide: 48 });
    const meta = await sharp(cropped).metadata();

    assert.strictEqual(meta.width, w);
    assert.strictEqual(meta.height, h);
  });

  test('tightCropCell scales fragment to contain square when containFallback set', async () => {
    const w = 256;
    const h = 128;
    const raw = Buffer.alloc(w * h * 4, 0);

    for (let i = 0; i < w * h; i++) {
      raw[i * 4] = 192;
      raw[i * 4 + 1] = 192;
      raw[i * 4 + 2] = 192;
      raw[i * 4 + 3] = 255;
    }

    for (let y = 60; y < 65; y++) {
      for (let x = 20; x < 230; x++) {
        const i = (y * w + x) * 4;
        raw[i] = 20;
        raw[i + 1] = 20;
        raw[i + 2] = 20;
        raw[i + 3] = 255;
      }
    }

    const png = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
    const cropped = await tightCropCell(png, {
      minMaxSideRatio: 0.25,
      minCropMinSide: 48,
      containFallback: true,
    });
    const meta = await sharp(cropped).metadata();

    assert.strictEqual(meta.width, meta.height);
    assert.ok(meta.width! >= 200);
  });
});
