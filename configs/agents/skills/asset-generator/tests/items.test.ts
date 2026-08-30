import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  ItemsParseError,
  extractLeadingId,
  parseCellSpecs,
  validateGenerationGate,
  validateGridCells,
} from '../src/items.js';

describe('items parser (strict, Windows-safe)', () => {
  test('parses inline JSON array on non-Windows or via @file', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asset-items-'));
    const file = path.join(dir, 'cells.json');
    fs.writeFileSync(file, JSON.stringify(['Cell A', 'Cell B', 'Cell C', 'Cell D']));

    const items = parseCellSpecs(undefined, `@${file}`, dir);
    assert.strictEqual(items.length, 4);
    assert.strictEqual(items[0].prompt, 'Cell A');
  });

  test('blocks inline JSON on Windows', () => {
    if (process.platform !== 'win32') return;
    assert.throws(
      () => parseCellSpecs(undefined, '["a","b","c","d"]'),
      (err: Error) => err instanceof ItemsParseError && err.message.includes('blocked on Windows'),
    );
  });

  test('parses { id, prompt } objects', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asset-items-'));
    const file = path.join(dir, 'cells.json');
    fs.writeFileSync(
      file,
      JSON.stringify([
        { id: 'window_bevel', prompt: 'FINANCIAL / FANTASY wordmark with bevel frame' },
        { id: 'crystal_flat', prompt: 'Flat crystal wordmark' },
        { id: 'minimal', prompt: 'Minimal vector logo' },
        { id: 'neon', prompt: 'Neon arcade title' },
      ]),
    );

    const specs = parseCellSpecs(undefined, `@${file}`, dir);
    assert.strictEqual(specs[0].id, 'window_bevel');
    assert.ok(specs[0].prompt.includes('FINANCIAL'));
  });

  test('extractLeadingId from "Cell A: description"', () => {
    assert.strictEqual(extractLeadingId('Cell A: FINANCIAL wordmark'), 'a');
    assert.strictEqual(extractLeadingId('B: crystal frame'), 'b');
  });

  test('throws on malformed JSON instead of silent fallback', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asset-items-'));
    const file = path.join(dir, 'bad.json');
    fs.writeFileSync(file, '["broken", json]');
    assert.throws(() => parseCellSpecs(undefined, `@${file}`, dir), ItemsParseError);
  });

  test('validateGridCells rejects count mismatch', () => {
    assert.throws(
      () => validateGridCells([{ prompt: 'only one' }], 4),
      ItemsParseError,
    );
  });

  test('validateGenerationGate requires matching token and grill ack', () => {
    assert.throws(() => validateGenerationGate({}, 'abc'), ItemsParseError);
    assert.throws(() => validateGenerationGate({ confirmToken: 'wrong' }, 'abc'), ItemsParseError);
    assert.throws(() => validateGenerationGate({ confirmToken: 'abc' }, 'abc'), ItemsParseError);
    assert.doesNotThrow(() => validateGenerationGate({ printPrompt: true }, 'abc'));
    assert.doesNotThrow(() => validateGenerationGate({ confirmToken: 'abc', skipGrillAck: true }, 'abc'));
    assert.doesNotThrow(() => validateGenerationGate({ confirmToken: 'abc', skipGrillAck: true }, 'abc', 'single'));
  });

  test('does not comma-split theme prompt', () => {
    const specs = parseCellSpecs(undefined, undefined);
    assert.deepStrictEqual(specs, []);
    assert.throws(() => validateGridCells(specs, 4), ItemsParseError);
  });

  test('accepts plain cells.json without @ (PowerShell splat workaround)', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asset-items-'));
    const file = path.join(dir, 'cells.json');
    fs.writeFileSync(file, JSON.stringify(['A', 'B', 'C', 'D']));
    const specs = parseCellSpecs(undefined, 'cells.json', dir);
    assert.strictEqual(specs.length, 4);
  });
});
