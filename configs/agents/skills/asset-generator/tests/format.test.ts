import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {
  encodeCellImage,
  extensionForFormat,
  inferOutputFormatFromFilename,
  clampEncodingQuality,
  sharpFormatForOutput,
  formatFromExtension,
  normalizeCustomFilename,
  parseOutputFormat,
  resolveOutputFormat,
} from '../src/format.js';

describe('output format helpers', () => {
  test('parseOutputFormat accepts aliases', () => {
    assert.strictEqual(parseOutputFormat('webp'), 'webp');
    assert.strictEqual(parseOutputFormat('PNG'), 'png');
    assert.strictEqual(parseOutputFormat('jpeg'), 'jpeg');
    assert.strictEqual(parseOutputFormat('jpg'), 'jpeg');
    assert.strictEqual(parseOutputFormat('gif'), null);
  });

  test('formatFromExtension maps common extensions', () => {
    assert.strictEqual(formatFromExtension('.webp'), 'webp');
    assert.strictEqual(formatFromExtension('png'), 'png');
    assert.strictEqual(formatFromExtension('.jpg'), 'jpeg');
    assert.strictEqual(formatFromExtension('.jpeg'), 'jpeg');
  });

  test('resolveOutputFormat prefers explicit -f over -o extension', () => {
    assert.strictEqual(resolveOutputFormat('png', 'hero.webp'), 'png');
    assert.strictEqual(resolveOutputFormat(undefined, 'hero.jpg'), 'jpeg');
    assert.strictEqual(resolveOutputFormat(undefined, undefined), 'webp');
  });

  test('normalizeCustomFilename aligns extension with format', () => {
    assert.strictEqual(normalizeCustomFilename('hero.webp', 'jpeg'), 'hero.jpg');
    assert.strictEqual(normalizeCustomFilename('hero.png', 'webp'), 'hero.webp');
    assert.strictEqual(normalizeCustomFilename('out/logo', 'png'), 'out/logo');
  });

  test('encodeCellImage writes matching sharp format', async () => {
    const rgba = await sharp({
      create: {
        width: 32,
        height: 32,
        channels: 4,
        background: { r: 0, g: 128, b: 255, alpha: 0.5 },
      },
    })
      .png()
      .toBuffer();

    for (const format of ['webp', 'png', 'jpeg'] as const) {
      const encoded = await encodeCellImage(rgba, format, 80);
      const meta = await sharp(encoded).metadata();
      assert.strictEqual(meta.format, format === 'jpeg' ? 'jpeg' : format);
    }
  });

  test('clampEncodingQuality bounds 1-100', () => {
    assert.strictEqual(clampEncodingQuality(0), 1);
    assert.strictEqual(clampEncodingQuality(150), 100);
    assert.strictEqual(clampEncodingQuality(80), 80);
  });

  test('inferOutputFormatFromFilename', () => {
    assert.strictEqual(inferOutputFormatFromFilename('cell.jpg'), 'jpeg');
    assert.strictEqual(inferOutputFormatFromFilename('cell.webp'), 'webp');
  });

  test('sharpFormatForOutput maps jpeg to sharp jpeg', () => {
    assert.strictEqual(sharpFormatForOutput('jpeg'), 'jpeg');
    assert.strictEqual(sharpFormatForOutput('png'), 'png');
  });
});
