import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, test } from "node:test";
import sharp from "sharp";
import { detectGridSeams, isMagentaPixel } from "../src/grid-detect.js";

describe("grid detect", () => {
  test("isMagentaPixel accurately detects magenta color", () => {
    assert.ok(isMagentaPixel(255, 0, 255));
    assert.ok(isMagentaPixel(240, 20, 240));
    assert.ok(!isMagentaPixel(192, 192, 192)); // Gray
    assert.ok(!isMagentaPixel(0, 0, 0)); // Black
    assert.ok(!isMagentaPixel(255, 255, 255)); // White
  });

  test("detects seams on synthetic 2x2 grid image with magenta lines", async () => {
    const width = 200;
    const height = 200;
    // Create 200x200 gray image with magenta vertical line at x=100 and horizontal line at y=100
    const rawBuffer = Buffer.alloc(width * height * 3, 192); // Gray #C0C0C0

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = (y * width + x) * 3;
        if (x === 100 || y === 100) {
          rawBuffer[idx] = 255; // R
          rawBuffer[idx + 1] = 0; // G
          rawBuffer[idx + 2] = 255; // B
        }
      }
    }

    const tmpPath = path.join(os.tmpdir(), `test-grid-${Date.now()}.png`);
    await sharp(rawBuffer, { raw: { width, height, channels: 3 } })
      .png()
      .toFile(tmpPath);

    try {
      const meta = await detectGridSeams(tmpPath, 2, 2);
      assert.strictEqual(meta.cols, 2);
      assert.strictEqual(meta.rows, 2);
      assert.strictEqual(meta.bands.length, 4);
      assert.strictEqual(meta.colSeams[0], 100);
      assert.strictEqual(meta.rowSeams[0], 100);
      assert.strictEqual(meta.detector, 'magenta');
      assert.strictEqual(meta.bands[0].width, 100);
      assert.strictEqual(meta.bands[0].height, 100);
    } finally {
      if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
    }
  });

  test("falls back to equal-split if no seams detected", async () => {
    const width = 300;
    const height = 300;
    const rawBuffer = Buffer.alloc(width * height * 3, 192); // Solid gray, no lines
    const tmpPath = path.join(os.tmpdir(), `test-plain-${Date.now()}.png`);
    await sharp(rawBuffer, { raw: { width, height, channels: 3 } })
      .png()
      .toFile(tmpPath);

    try {
      const meta = await detectGridSeams(tmpPath, 3, 3);
      assert.strictEqual(meta.cols, 3);
      assert.strictEqual(meta.rows, 3);
      assert.strictEqual(meta.bands.length, 9);
      assert.strictEqual(meta.colSeams.length, 2);
      assert.strictEqual(meta.rowSeams.length, 2);
      assert.strictEqual(meta.colSeams[0], 100);
      assert.strictEqual(meta.colSeams[1], 200);
      assert.strictEqual(meta.detector, 'equal-split');
    } finally {
      if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
    }
  });
});
