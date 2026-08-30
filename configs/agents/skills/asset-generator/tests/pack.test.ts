import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { normalizeAssetContain, slugifyLabel, slugifyTitle, formatCellFilename } from '../src/pack.js';

describe('pack & slug naming', () => {
  test('formatCellFilename uses explicit id over slugified fragments', () => {
    assert.strictEqual(formatCellFilename('window_bevel', 'FANTASY below cyan glow', 0), '01_window_bevel');
    assert.strictEqual(formatCellFilename(undefined, 'A friendly robot face', 0), '01_robot_face');
  });

  test('slugifyLabel generates clean semantic filenames with index prefix', () => {
    assert.strictEqual(
      slugifyLabel('A friendly 3D robot face with blue visor', 0),
      '01_robot_face_blue_visor'
    );
    assert.strictEqual(
      slugifyLabel('Cloud sync server with rotating arrows', 1),
      '02_cloud_sync_server_rotating'
    );
    assert.strictEqual(
      slugifyLabel('Golden security padlock with keyhole', 2),
      '03_golden_security_padlock_keyhole'
    );
    assert.strictEqual(
      slugifyLabel('Item 4', 3),
      '04_item'
    );
  });

  test('slugifyTitle generates clean single hero slug', () => {
    assert.strictEqual(
      slugifyTitle('AI Workspace Studio Platform'),
      'ai_workspace_studio_platform'
    );
  });

  test('normalizes a non-square asset into a clean square canvas with padding', async () => {
    const rawRect = Buffer.alloc(100 * 200 * 4);
    for (let i = 0; i < 100 * 200; i++) {
      rawRect[i * 4] = 255;
      rawRect[i * 4 + 1] = 0;
      rawRect[i * 4 + 2] = 0;
      rawRect[i * 4 + 3] = 255;
    }
    const inputPng = await sharp(rawRect, { raw: { width: 100, height: 200, channels: 4 } }).png().toBuffer();

    const normalized = await normalizeAssetContain(inputPng, 512, 10);
    const meta = await sharp(normalized).metadata();

    assert.strictEqual(meta.width, 512);
    assert.strictEqual(meta.height, 512);
    assert.strictEqual(meta.channels, 4);
  });

  test('verifies cloud re-extraction has 0 black lines after fix', async () => {
    const dir = path.resolve(process.cwd(), 'src/assets/images/generated/live_e2e_features');
    if (!fs.existsSync(dir)) return;

    const gridMeta = JSON.parse(fs.readFileSync(path.join(dir, 'sheet.grid.json'), 'utf-8'));
    const transparentPath = path.join(dir, 'sheet.transparent.png');

    // Run clearSeamCorridors
    const { clearSeamCorridors, extractAndSaveAssets } = await import('../src/pack.js');
    const corridorCleared = await clearSeamCorridors(transparentPath, gridMeta);

    // Re-extract assets with fixed pack.ts
    const manifest = await extractAndSaveAssets(
      corridorCleared,
      gridMeta,
      dir,
      { countOrGrid: '4', prompt: 'AI SaaS Core Features', style: 'clay', pad: 10, format: 'webp', quality: 80 },
      [
        'A friendly 3D robot head with glowing cyan visor and smiling face',
        'A volumetric cloud sculpture with dual pastel blue sync arrows',
        'A golden brass security padlock with glowing keyhole',
        'A rising 3D bar chart with three cylindrical pillars'
      ],
      'live_e2e_features'
    );

    const cloudItem = manifest.items.find(i => i.filename.includes('cloud'));
    assert.ok(cloudItem, 'Cloud item must exist in manifest');

    const cloudBuf = await sharp(cloudItem.path).ensureAlpha().raw().toBuffer();
    const meta = await sharp(cloudItem.path).metadata();
    const cw = meta.width!;
    const ch = meta.height!;

    let darkBorderPixelCount = 0;
    for (let y = 0; y < ch; y++) {
      for (let x = cw - 10; x < cw; x++) {
        const idx = (y * cw + x) * 4;
        const r = cloudBuf[idx];
        const g = cloudBuf[idx + 1];
        const b = cloudBuf[idx + 2];
        const a = cloudBuf[idx + 3];
        if (r === 0 && g === 0 && b === 0 && a > 100) {
          darkBorderPixelCount++;
        }
      }
    }

    console.log(`\n✅ Post-fix dark border pixels on cloud right edge: ${darkBorderPixelCount}`);
    assert.strictEqual(darkBorderPixelCount, 0, 'There must be ZERO dark border pixels on the right edge of the cloud!');
  });

  test('validates 3x3 glossy and 4x4 flat live batches have zero border artifacts', async () => {
    const root = path.resolve(process.cwd(), 'src/assets/images/generated');

    async function checkBatch(batchName: string, expectedCount: number) {
      const bDir = path.join(root, batchName);
      if (!fs.existsSync(bDir)) return;

      const manifest = JSON.parse(fs.readFileSync(path.join(bDir, 'manifest.json'), 'utf-8'));
      assert.strictEqual(manifest.items.length, expectedCount, `Batch ${batchName} must contain ${expectedCount} items`);

      for (const item of manifest.items) {
        assert.ok(fs.existsSync(item.path), `File ${item.filename} must exist`);
        const meta = await sharp(item.path).metadata();
        assert.strictEqual(meta.format, 'webp', `Format of ${item.filename} must be webp`);
        assert.strictEqual(meta.width, meta.height, `Dimensions of ${item.filename} must be a square`);

        const buf = await sharp(item.path).ensureAlpha().raw().toBuffer();
        const w = meta.width!;
        const h = meta.height!;

        let blackArtifacts = 0;
        for (let y = 0; y < h; y++) {
          for (let x = 0; x < w; x++) {
            const isBorder = (x < 5 || x >= w - 5 || y < 5 || y >= h - 5);
            if (isBorder) {
              const idx = (y * w + x) * 4;
              const r = buf[idx];
              const g = buf[idx + 1];
              const b = buf[idx + 2];
              const a = buf[idx + 3];
              if (r === 0 && g === 0 && b === 0 && a > 100) {
                blackArtifacts++;
              }
            }
          }
        }
        assert.strictEqual(blackArtifacts, 0, `File ${item.filename} must have 0 black border artifacts`);
      }
      console.log(`✅ Batch ${batchName} (${expectedCount} items) verified with 0 border artifacts!`);
    }

    await checkBatch('live_3x3_glossy', 9);
    await checkBatch('live_4x4_flat', 16);
  });
});
