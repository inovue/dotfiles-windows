import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { STYLE_PRESETS, resolveStyle } from "../src/presets.js";

describe("presets", () => {
  test("resolves exact style id", () => {
    const clay = resolveStyle("clay");
    assert.ok(clay);
    assert.strictEqual(clay.id, "clay");
  });

  test("resolves style aliases", () => {
    const clay1 = resolveStyle("3d-clay");
    assert.ok(clay1);
    assert.strictEqual(clay1.id, "clay");

    const glass = resolveStyle("glassmorphism");
    assert.ok(glass);
    assert.strictEqual(glass.id, "glass");

    const real = resolveStyle("photo-object");
    assert.ok(real);
    assert.strictEqual(real.id, "real");
  });

  test("returns undefined for unknown style", () => {
    assert.strictEqual(resolveStyle("unknown-style-xyz"), undefined);
    assert.strictEqual(resolveStyle(undefined), undefined);
  });

  test("contains all 14 presets", () => {
    assert.ok(Object.keys(STYLE_PRESETS).length >= 14);
  });
});
