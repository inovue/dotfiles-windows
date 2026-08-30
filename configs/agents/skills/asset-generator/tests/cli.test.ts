import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { parseArgs } from '../src/cli.js';
import { buildPrompt } from '../src/prompt.js';

describe('cli parser (with reference images and model quality)', () => {
  test('defaults modelQuality to low', () => {
    const opts = parseArgs(['-g', '4', 'Mascot Icons']);
    assert.strictEqual(opts.modelQuality, 'low');
  });

  test('parses --mq and --model-quality flags', () => {
    const opts1 = parseArgs(['-g', '4', 'Icons', '--mq', 'high']);
    assert.strictEqual(opts1.modelQuality, 'high');

    const opts2 = parseArgs(['-g', '4', 'Icons', '--model-quality', 'medium']);
    assert.strictEqual(opts2.modelQuality, 'medium');
  });

  test('parses -r and -m flags for reference image and mode', () => {
    const opts = parseArgs(['-g', '4', 'Mascot Icons', '-r', './mascot.png', '-m', 'character', '-s', 'clay']);
    assert.strictEqual(opts.countOrGrid, '4');
    assert.strictEqual(opts.prompt, 'Mascot Icons');
    assert.strictEqual(opts.refImages?.length, 1);
    assert.strictEqual(opts.refImages?.[0], './mascot.png');
    assert.strictEqual(opts.refMode, 'character');
  });

  test('parses --items @file.json path', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asset-cli-'));
    const file = path.join(dir, 'cells.json');
    fs.writeFileSync(file, JSON.stringify(['A', 'B', 'C', 'D']));

    const opts = parseArgs(['-g', '4', 'Theme', '--items', `@${file}`]);
    const built = buildPrompt({ ...opts, printPrompt: true });
    assert.deepStrictEqual(built.itemsList, ['A', 'B', 'C', 'D']);
  });

  test('parses --preset wordmark (high quality + tight)', () => {
    const opts = parseArgs(['-g', '4x2', 'Wordmarks', '--preset', 'wordmark']);
    assert.strictEqual(opts.preset, 'wordmark');
    assert.strictEqual(opts.modelQuality, 'high');
    assert.strictEqual(opts.tight, true);
    assert.strictEqual(opts.countOrGrid, '4x2');
  });

  test('parses --format png and jpeg aliases', () => {
    assert.strictEqual(parseArgs(['-g', '4', 'Theme', '-f', 'png']).format, 'png');
    assert.strictEqual(parseArgs(['-g', '4', 'Theme', '--format', 'jpeg']).format, 'jpeg');
    assert.strictEqual(parseArgs(['-g', '4', 'Theme', '-f', 'jpg']).format, 'jpeg');
  });
});
