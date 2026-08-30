import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  buildFalImageInput,
  GPT_IMAGE_EDIT_MODEL,
  GPT_IMAGE_GENERATE_MODEL,
} from '../src/fal.js';

const MINI_PNG_B64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

function writeMiniPng(dir: string, name: string): string {
  const file = path.join(dir, name);
  fs.writeFileSync(file, Buffer.from(MINI_PNG_B64, 'base64'));
  return file;
}

describe('buildFalImageInput', () => {
  test('no refs → generate model, no image_urls', () => {
    const { modelId, input, refCount } = buildFalImageInput('test prompt', {});
    assert.strictEqual(modelId, GPT_IMAGE_GENERATE_MODEL);
    assert.strictEqual(refCount, 0);
    assert.strictEqual(input.image_url, undefined);
    assert.strictEqual(input.image_urls, undefined);
  });

  test('single ref → edit model with image_urls array (gpt-image-2/edit schema)', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fal-ref-'));
    const ref = writeMiniPng(dir, 'ref.png');

    const { modelId, input, refCount } = buildFalImageInput('edit prompt', { refImages: [ref] });

    assert.strictEqual(modelId, GPT_IMAGE_EDIT_MODEL);
    assert.strictEqual(refCount, 1);
    assert.ok(Array.isArray(input.image_urls), 'image_urls must be an array');
    assert.strictEqual((input.image_urls as string[]).length, 1);
    assert.match((input.image_urls as string[])[0], /^data:image\/png;base64,/);
    assert.strictEqual(input.image_url, (input.image_urls as string[])[0]);
  });

  test('multiple refs → image_urls array with primary image_url', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fal-refs-'));
    const ref1 = writeMiniPng(dir, 'a.png');
    const ref2 = writeMiniPng(dir, 'b.png');

    const { modelId, input, refCount } = buildFalImageInput('edit prompt', {
      refImages: [ref1, ref2],
    });

    assert.strictEqual(modelId, GPT_IMAGE_EDIT_MODEL);
    assert.strictEqual(refCount, 2);
    assert.strictEqual((input.image_urls as string[]).length, 2);
    assert.strictEqual(input.image_url, (input.image_urls as string[])[0]);
  });
});
