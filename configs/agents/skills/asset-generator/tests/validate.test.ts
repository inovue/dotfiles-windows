import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { validateGridSeams, measureAlphaCoverage, validateCellAlphaCoverage, validateCellDimensions, PipelineValidationError } from '../src/validate.js';
import type { GridMeta } from '../src/types.js';

function fakeGridMeta(detector: GridMeta['detector']): GridMeta {
  return {
    version: 1,
    cols: 2,
    rows: 2,
    srcSize: [1024, 1024],
    keyColor: '#C0C0C0',
    separatorColor: '#FF00FF',
    bands: [],
    colSeams: [512],
    rowSeams: [512],
    detector,
    seamConfidence: { col: [0.8], row: [0.01] },
    magentaSeamHits: detector === 'magenta' ? 2 : 0,
    totalSeams: 2,
  };
}

describe('pipeline quality gates', () => {
  test('validateGridSeams rejects weak-magenta by default', () => {
    assert.throws(
      () => validateGridSeams(fakeGridMeta('weak-magenta')),
      PipelineValidationError,
    );
    assert.doesNotThrow(() => validateGridSeams(fakeGridMeta('weak-magenta'), { allowWeakSeams: true }));
    assert.doesNotThrow(() => validateGridSeams(fakeGridMeta('magenta')));
  });

  test('validateCellAlphaCoverage rejects near-empty cells', async () => {
    const empty = await sharp({
      create: { width: 64, height: 64, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
    }).png().toBuffer();

    await assert.rejects(
      () => validateCellAlphaCoverage(empty, 'test cell', 0),
      PipelineValidationError,
    );
  });

  test('measureAlphaCoverage on solid shape', async () => {
    const buf = Buffer.alloc(100 * 100 * 4, 0);
    for (let i = 0; i < 100 * 50; i++) {
      buf[i * 4 + 3] = 255;
    }
    const png = await sharp(buf, { raw: { width: 100, height: 100, channels: 4 } }).png().toBuffer();
    const cov = await measureAlphaCoverage(png);
    assert.ok(cov > 0.45 && cov < 0.55);
  });

  test('validateCellDimensions rejects tiny exports', () => {
    assert.throws(
      () => validateCellDimensions(16, 64, 'tiny', 0),
      PipelineValidationError,
    );
    assert.doesNotThrow(() => validateCellDimensions(64, 32, 'ok', 0));
  });
});
