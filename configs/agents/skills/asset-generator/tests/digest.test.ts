import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { computeBatchDigest, computeGrillAckToken } from '../src/digest.js';
import { validateGenerationGate } from '../src/items.js';
import { ItemsParseError } from '../src/items.js';
import { buildPrompt } from '../src/prompt.js';

describe('batch digest & confirm token', () => {
  const cells = [
    { id: 'a', prompt: 'Cell A motif' },
    { id: 'b', prompt: 'Cell B motif' },
    { id: 'c', prompt: 'Cell C motif' },
    { id: 'd', prompt: 'Cell D motif' },
  ];

  test('computeBatchDigest is stable for same inputs', () => {
    const opts = { countOrGrid: '4', style: 'flat', modelQuality: 'high' as const, tight: true, rembg: true };
    const t1 = computeBatchDigest(4, 'Theme', cells, opts);
    const t2 = computeBatchDigest(4, 'Theme', cells, opts);
    assert.strictEqual(t1, t2);
    assert.match(t1, /^[a-f0-9]{12}$/);
  });

  test('digest changes when cells change', () => {
    const opts = { countOrGrid: '4' };
    const t1 = computeBatchDigest(4, 'Theme', cells, opts);
    const t2 = computeBatchDigest(4, 'Theme', [...cells.slice(0, 3), { id: 'x', prompt: 'different' }], opts);
    assert.notStrictEqual(t1, t2);
  });

  test('digest changes when output format changes', () => {
    const opts = { countOrGrid: '4' };
    const webp = computeBatchDigest(4, 'Theme', cells, { ...opts, format: 'webp' as const });
    const jpeg = computeBatchDigest(4, 'Theme', cells, { ...opts, format: 'jpeg' as const });
    assert.notStrictEqual(webp, jpeg);
  });

  test('digest changes when explicit outDirResolved changes', () => {
    const opts = { countOrGrid: '4' };
    const a = computeBatchDigest(4, 'Theme', cells, { ...opts, outDirResolved: '/tmp/out-a' });
    const b = computeBatchDigest(4, 'Theme', cells, { ...opts, outDirResolved: '/tmp/out-b' });
    assert.notStrictEqual(a, b);
  });

  test('validateGenerationGate requires matching token and grill ack', () => {
    const token = computeBatchDigest(4, 'Theme', cells, { countOrGrid: '4' });
    const grill = computeGrillAckToken(token);
    assert.throws(() => validateGenerationGate({}, token), ItemsParseError);
    assert.throws(() => validateGenerationGate({ confirmToken: 'wrong' }, token), ItemsParseError);
    assert.throws(() => validateGenerationGate({ confirmToken: token }, token), ItemsParseError);
    assert.doesNotThrow(() => validateGenerationGate({ printPrompt: true }, token));
    assert.doesNotThrow(() => validateGenerationGate({ confirmToken: token, grillAck: grill }, token));
    assert.doesNotThrow(() => validateGenerationGate({ confirmToken: token, skipGrillAck: true }, token));
  });

  test('single hero generation also requires confirm token', () => {
    assert.throws(
      () => buildPrompt({ prompt: 'Hero KV', style: 'glass', aspect: '16:9', composition: 'right-heavy' }),
      ItemsParseError,
    );
    const dry = buildPrompt({
      prompt: 'Hero KV',
      style: 'glass',
      aspect: '16:9',
      composition: 'right-heavy',
      printPrompt: true,
    });
    assert.ok(dry.confirmToken.length === 12);
  });
});
