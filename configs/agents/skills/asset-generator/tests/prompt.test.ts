import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { buildPrompt, parseGridCount, getCellShapeHint } from '../src/prompt.js';
import { ItemsParseError } from '../src/items.js';
import { PipelineValidationError } from '../src/validate.js';

const FOUR_CELLS = [
  'Cell A motif',
  'Cell B motif',
  'Cell C motif',
  'Cell D motif',
];

const GRID_OPTS = { printPrompt: true as const };

describe('prompt builder (with Reference Modes)', () => {
  test('injects character identity instruction when refMode is character', () => {
    const res = buildPrompt({
      countOrGrid: '4',
      prompt: 'Mascot in 4 daily activities',
      refMode: 'character',
      refImages: ['./avatar.png'],
      items: FOUR_CELLS,
      ...GRID_OPTS,
    });
    assert.strictEqual(res.gridInfo.total, 4);
    assert.ok(res.prompt.includes('Strictly maintain the exact character / mascot identity'));
    assert.ok(res.prompt.includes('Cell A motif'));
  });

  test('injects style replication instruction when refMode is style', () => {
    const res = buildPrompt({
      countOrGrid: '9',
      prompt: 'UI Tools',
      refMode: 'style',
      refImages: ['./moodboard.png'],
      items: Array.from({ length: 9 }, (_, i) => `Tool ${i + 1}`),
      ...GRID_OPTS,
    });
    assert.strictEqual(res.gridInfo.total, 9);
    assert.ok(res.prompt.includes('Extract and strictly replicate the exact artistic rendering style'));
  });

  test('grid prompt uses exact cell items without generic fallback', () => {
    const res = buildPrompt({
      countOrGrid: '4',
      prompt: 'Brand Logos',
      items: FOUR_CELLS,
      ...GRID_OPTS,
    });
    assert.ok(!res.prompt.includes('relating to'));
    for (const cell of FOUR_CELLS) {
      assert.ok(res.prompt.includes(cell));
    }
  });

  test('logo preset injects typography anti-drift rule', () => {
    const res = buildPrompt({
      countOrGrid: '4',
      prompt: 'Brand Logos',
      items: FOUR_CELLS,
      preset: 'logo',
      ...GRID_OPTS,
    });
    assert.ok(res.prompt.includes('Typography rule:'));
    assert.ok(res.prompt.includes('Never replace a text cell with icons'));
  });
});

describe('parseGridCount', () => {
  test('supports NxM grids', () => {
    assert.deepStrictEqual(parseGridCount('2x4'), { cols: 2, rows: 4, total: 8 });
    assert.deepStrictEqual(parseGridCount('4x2'), { cols: 4, rows: 2, total: 8 });
  });
});

describe('getCellShapeHint', () => {
  test('landscape hint for wide grids (4x2)', () => {
    const hint = getCellShapeHint(4, 2);
    assert.ok(hint?.includes('landscape'));
    assert.ok(hint?.includes('wordmark'));
  });

  test('portrait hint for tall grids (2x4)', () => {
    const hint = getCellShapeHint(2, 4);
    assert.ok(hint?.includes('portrait'));
  });

  test('4x2 grid prompt includes landscape cell shape', () => {
    const res = buildPrompt({
      countOrGrid: '4x2',
      prompt: 'Brand Wordmarks',
      preset: 'wordmark',
      items: Array.from({ length: 8 }, (_, i) => `Wordmark ${i + 1}`),
      ...GRID_OPTS,
    });
    assert.strictEqual(res.gridInfo.cols, 4);
    assert.strictEqual(res.gridInfo.rows, 2);
    assert.ok(res.prompt.includes('landscape'));
    assert.ok(res.prompt.includes('Subject Framing'));
  });
});

describe('output format gates', () => {
  test('blocks JPEG for logo preset without --allow-jpeg-logos', () => {
    assert.throws(
      () => buildPrompt({
        countOrGrid: '4',
        prompt: 'Brand Logos',
        preset: 'logo',
        format: 'jpeg',
        items: FOUR_CELLS,
        ...GRID_OPTS,
      }),
      PipelineValidationError,
    );
  });

  test('allows JPEG for logo preset with --allow-jpeg-logos', () => {
    const res = buildPrompt({
      countOrGrid: '4',
      prompt: 'Brand Logos',
      preset: 'logo',
      format: 'jpeg',
      allowJpegLogos: true,
      items: FOUR_CELLS,
      ...GRID_OPTS,
    });
    assert.strictEqual(res.gridInfo.total, 4);
    assert.strictEqual(res.confirmToken.length, 12);
  });
});
