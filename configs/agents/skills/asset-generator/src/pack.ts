import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';
import { applyChromaKeyInPlace, getLargestOpaqueBBox } from './chroma.js';
import { encodeCellImage, extensionForFormat, DEFAULT_ENCODING_QUALITY, JPEG_FLATTEN_BACKGROUND } from './format.js';
import { validateCellAlphaCoverage, validateCellDimensions } from './validate.js';
import type { AssetManifest, AssetManifestItem, CellSpec, GeneratorOptions, GridMeta } from './types.js';

export const SEAM_CLEAR_HALF = 5;

/** Stable filename from explicit cell id or slugified label. */
export function formatCellFilename(id: string | undefined, label: string, index: number): string {
  if (id) {
    const clean = id
      .toLowerCase()
      .replace(/[^a-z0-9\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF_-]/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '')
      .slice(0, 32);
    if (clean) {
      return `${String(index + 1).padStart(2, '0')}_${clean}`;
    }
  }
  return slugifyLabel(label, index);
}

/**
 * Creates a clean, descriptive slug filename from an item description/label.
 * Example: "A friendly 3D robot face with blue visor" -> "01_robot_face_blue_visor"
 */
export function slugifyLabel(label: string, index: number): string {
  const prefix = String(index + 1).padStart(2, '0');
  if (!label || /^item\s*\d*$/i.test(label.trim())) {
    return `${prefix}_item`;
  }

  // Remove common filler words and prepositions
  let clean = label
    .replace(/^(a|an|the)\s+/i, '')
    .replace(/\b(3d|matte|clay|glossy|glass|vector|flat|isolated|volumetric|smooth|chunky|icon|badge|asset|friendly)\b/gi, ' ')
    .replace(/\b(with|and|of|in|on|at|for|the|a|an|by)\b/gi, ' ')
    .replace(/[()[\]{}'":;,.!?/\\|]/g, ' ')
    .trim();

  // Convert to lowercase and underscore slug
  clean = clean
    .toLowerCase()
    .replace(/[^a-z0-9\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\s_-]/g, '')
    .trim()
    .replace(/[\s-]+/g, '_')
    .replace(/_+/g, '_');

  // Limit to 4 key words or max 32 characters
  const words = clean.split('_').filter(Boolean).slice(0, 4);
  const shortSlug = words.join('_').slice(0, 32).replace(/_+$/, '');

  if (!shortSlug || /^item(_\d+)?$/i.test(shortSlug)) {
    return `${prefix}_item`;
  }

  return `${prefix}_${shortSlug}`;
}

export function slugifyTitle(title: string): string {
  if (!title) return 'hero';
  let clean = title
    .replace(/^(a|an|the)\s+/i, '')
    .replace(/\b(3d|matte|clay|glossy|glass|landing|page|website|illustration)\b/gi, ' ')
    .replace(/\b(with|and|of|in|on|at|for|the|a|an|by)\b/gi, ' ')
    .replace(/[()[\]{}'":;,.!?/\\|]/g, ' ')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\s_-]/g, '')
    .trim()
    .replace(/[\s-]+/g, '_')
    .replace(/_+/g, '_');

  const words = clean.split('_').filter(Boolean).slice(0, 4);
  const slug = words.join('_').slice(0, 36).replace(/_+$/, '');
  return slug || 'hero';
}

export async function clearSeamCorridors(
  imagePath: string,
  gridMeta: GridMeta,
): Promise<Buffer> {
  const image = sharp(imagePath);
  const { width, height } = (await image.metadata()) as { width: number; height: number };
  const raw = await image.ensureAlpha().raw().toBuffer();

  const colSeams = gridMeta.colSeams;
  const rowSeams = gridMeta.rowSeams;

  // Clear inner vertical seams
  for (const seamX of colSeams) {
    const startX = Math.max(0, seamX - SEAM_CLEAR_HALF);
    const endX = Math.min(width - 1, seamX + SEAM_CLEAR_HALF);
    for (let x = startX; x <= endX; x++) {
      for (let y = 0; y < height; y++) {
        const idx = (y * width + x) * 4;
        raw[idx + 3] = 0;
      }
    }
  }

  // Clear inner horizontal seams
  for (const seamY of rowSeams) {
    const startY = Math.max(0, seamY - SEAM_CLEAR_HALF);
    const endY = Math.min(height - 1, seamY + SEAM_CLEAR_HALF);
    for (let y = startY; y <= endY; y++) {
      for (let x = 0; x < width; x++) {
        const idx = (y * width + x) * 4;
        raw[idx + 3] = 0;
      }
    }
  }

  // Clear outer perimeter border (2px) to eliminate AI edge line artifacts
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < 2; x++) {
      raw[(y * width + x) * 4 + 3] = 0;
      raw[(y * width + (width - 1 - x)) * 4 + 3] = 0;
    }
  }
  for (let x = 0; x < width; x++) {
    for (let y = 0; y < 2; y++) {
      raw[(y * width + x) * 4 + 3] = 0;
      raw[((height - 1 - y) * width + x) * 4 + 3] = 0;
    }
  }

  return sharp(raw, {
    raw: {
      width,
      height,
      channels: 4,
    },
  }).png().toBuffer();
}

async function getContentBBox(
  cellBuffer: Buffer,
  options: { chromaKeyFirst?: boolean } = {},
): Promise<{ left: number; top: number; width: number; height: number } | null> {
  const image = sharp(cellBuffer);
  const meta = await image.metadata();
  const w = meta.width!;
  const h = meta.height!;
  const raw = Buffer.from(await image.ensureAlpha().raw().toBuffer());

  if (options.chromaKeyFirst) {
    applyChromaKeyInPlace(raw, w, h);
  }

  return getLargestOpaqueBBox(raw, w, h, 15);
}

/** Tight crop: chroma-key gray/magenta seams, then largest opaque component. */
export async function tightCropCell(
  cellBuffer: Buffer,
  options: { minMaxSideRatio?: number; minCropMinSide?: number; containFallback?: boolean } = {},
): Promise<Buffer> {
  const minRatio = options.minMaxSideRatio ?? 0.2;
  const minCropMinSide = options.minCropMinSide ?? 32;
  const image = sharp(cellBuffer);
  const meta = await image.metadata();
  const w = meta.width!;
  const h = meta.height!;
  const raw = Buffer.from(await image.ensureAlpha().raw().toBuffer());

  applyChromaKeyInPlace(raw, w, h);
  const bbox = getLargestOpaqueBBox(raw, w, h, 15);
  if (!bbox) {
    return cellBuffer;
  }

  const cropMax = Math.max(bbox.width, bbox.height);
  const cropMin = Math.min(bbox.width, bbox.height);
  const cellMax = Math.max(w, h);
  if (cropMax < cellMax * minRatio || cropMin < minCropMinSide) {
    const chromaKeyed = sharp(raw, { raw: { width: w, height: h, channels: 4 } });
    if (options.containFallback && bbox.width > 0 && bbox.height > 0) {
      const trimmed = await chromaKeyed
        .clone()
        .extract(bbox)
        .png()
        .toBuffer();
      return normalizeAssetContain(trimmed, cellMax, 12);
    }
    return chromaKeyed.png().toBuffer();
  }

  return sharp(raw, { raw: { width: w, height: h, channels: 4 } })
    .extract(bbox)
    .png()
    .toBuffer();
}

export async function normalizeAssetContain(
  cellBuffer: Buffer,
  targetSquareSize: number,
  padPercent: number = 10,
): Promise<Buffer> {
  const cell = sharp(cellBuffer);
  const meta = await cell.metadata();
  const cw = meta.width || targetSquareSize;
  const ch = meta.height || targetSquareSize;

  const bbox = await getContentBBox(cellBuffer);
  let trimmedBuffer: Buffer;
  let objW: number;
  let objH: number;

  if (bbox) {
    trimmedBuffer = await cell
      .extract({ left: bbox.left, top: bbox.top, width: bbox.width, height: bbox.height })
      .png()
      .toBuffer();
    objW = bbox.width;
    objH = bbox.height;
  } else {
    trimmedBuffer = cellBuffer;
    objW = cw;
    objH = ch;
  }

  const padRatio = Math.max(0, Math.min(0.45, padPercent / 100));
  const usableSize = Math.max(16, Math.round(targetSquareSize * (1 - padRatio * 2)));

  const scale = Math.min(usableSize / objW, usableSize / objH);
  const scaledW = Math.max(1, Math.round(objW * scale));
  const scaledH = Math.max(1, Math.round(objH * scale));

  // Scale object with EXPLICIT transparent background to prevent black padding lines
  const scaledObject = await sharp(trimmedBuffer)
    .resize(scaledW, scaledH, {
      fit: 'contain',
      kernel: 'lanczos3',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();

  const left = Math.round((targetSquareSize - scaledW) / 2);
  const top = Math.round((targetSquareSize - scaledH) / 2);

  const canvas = sharp({
    create: {
      width: targetSquareSize,
      height: targetSquareSize,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  });

  return canvas
    .composite([{ input: scaledObject, left, top }])
    .png()
    .toBuffer();
}

export async function extractAndSaveAssets(
  sheetBuffer: Buffer,
  gridMeta: GridMeta,
  outDir: string,
  options: GeneratorOptions,
  itemsList: string[],
  batchId: string,
  synthesizedPrompt?: string,
  cellSpecs?: CellSpec[],
): Promise<AssetManifest> {
  const format = options.format || 'webp';
  const ext = extensionForFormat(format);
  const quality = options.quality ?? DEFAULT_ENCODING_QUALITY;
  const padPercent = options.pad ?? 10;
  const manifestItems: AssetManifestItem[] = [];

  const baseImage = sharp(sheetBuffer);
  const total = gridMeta.bands.length;
  const cwd = process.cwd();

  for (const band of gridMeta.bands) {
    const spec = cellSpecs?.[band.index];
    const label = spec?.prompt ?? itemsList[band.index] ?? (total === 1 ? options.prompt : `Item ${band.index + 1}`);

    let filename: string;
    let itemId: string;
    const cellId = spec?.id;

    if (total === 1) {
      if (options.customFilename) {
        filename = options.customFilename;
        itemId = path.parse(filename).name;
      } else {
        const titleSlug = slugifyTitle(options.prompt);
        filename = `${titleSlug}.${ext}`;
        itemId = titleSlug;
      }
    } else {
      const slug = formatCellFilename(cellId, label, band.index);
      filename = `${slug}.${ext}`;
      itemId = slug;
    }

    const destPath = path.join(outDir, filename);

    const cellSharp = baseImage.clone().extract({
      left: band.left,
      top: band.top,
      width: band.width,
      height: band.height,
    });

    let processedCellBuffer = await cellSharp.png().toBuffer();

    if (total > 1) {
      if (options.rawCell) {
        processedCellBuffer = await cellSharp.png().toBuffer();
      } else if (options.tight) {
        const isLogoLike = options.preset === 'logo' || options.preset === 'wordmark';
        const minRatio = isLogoLike ? 0.25 : 0.2;
        const minCropMinSide = isLogoLike ? 48 : 32;
        processedCellBuffer = await tightCropCell(processedCellBuffer, {
          minMaxSideRatio: minRatio,
          minCropMinSide,
          containFallback: isLogoLike,
        });
      } else {
        const targetSquare = options.size || Math.max(band.width, band.height);
        processedCellBuffer = await normalizeAssetContain(
          processedCellBuffer,
          targetSquare,
          padPercent
        );
      }
    } else if (options.size) {
      processedCellBuffer = await sharp(processedCellBuffer)
        .resize(options.size, options.size, {
          fit: 'contain',
          background: { r: 0, g: 0, b: 0, alpha: 0 },
        })
        .png()
        .toBuffer();
    }

    const alphaCoverage = await validateCellAlphaCoverage(
      processedCellBuffer,
      label,
      band.index,
      { allowEmptyCells: options.allowEmptyCells },
    );

    const finalBuffer = await encodeCellImage(processedCellBuffer, format, quality);

    const finalMeta = await sharp(finalBuffer).metadata();
    const outW = finalMeta.width || band.width;
    const outH = finalMeta.height || band.height;
    validateCellDimensions(outW, outH, label, band.index);
    fs.writeFileSync(destPath, finalBuffer);

    // Calculate relative and Astro paths
    const relPath = path.relative(cwd, destPath).replace(/\\/g, '/');
    const astroPath = relPath.startsWith('src/')
      ? relPath.replace(/^src\//, '@/')
      : relPath;

    manifestItems.push({
      id: itemId,
      cellId,
      filename,
      index: band.index,
      row: band.row,
      col: band.col,
      label,
      alphaCoverage,
      width: finalMeta.width || band.width,
      height: finalMeta.height || band.height,
      path: destPath,
      relativePath: relPath,
      astroImportPath: astroPath,
    });
  }

  const manifest: AssetManifest = {
    version: 1,
    batchId,
    createdAt: new Date().toISOString(),
    mode: total > 1 ? 'grid' : 'single',
    grid: `${gridMeta.rows}x${gridMeta.cols}`,
    aspectRatio: options.aspect || '1:1',
    style: options.style,
    prompt: synthesizedPrompt || options.prompt,
    themePrompt: options.prompt,
    itemsList,
    cellSpecs,
    modelQuality: options.modelQuality || 'low',
    preset: options.preset,
    refImages: options.refImages,
    refMode: options.refMode,
    padPercent: total > 1 && !options.tight && !options.rawCell ? padPercent : undefined,
    outputFormat: format,
    encodingQuality: quality,
    jpegBackground: format === 'jpeg' ? JPEG_FLATTEN_BACKGROUND : undefined,
    items: manifestItems,
    files: {
      raw: path.join(outDir, 'sheet.raw.png'),
      transparent: path.join(outDir, 'sheet.transparent.png'),
      gridMeta: path.join(outDir, 'sheet.grid.json'),
    },
  };

  fs.writeFileSync(
    path.join(outDir, 'manifest.json'),
    JSON.stringify(manifest, null, 2) + '\n'
  );

  return manifest;
}
