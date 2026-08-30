import sharp from 'sharp';
import fs from 'node:fs';

export const CHROMA_KEY_RGB: [number, number, number] = [192, 192, 192];
export const SEPARATOR_RGB: [number, number, number] = [255, 0, 255];

export interface BBox {
  left: number;
  top: number;
  width: number;
  height: number;
}

export function isChromaKeyPixel(r: number, g: number, b: number): boolean {
  return (
    Math.abs(r - CHROMA_KEY_RGB[0]) < 25 &&
    Math.abs(g - CHROMA_KEY_RGB[1]) < 25 &&
    Math.abs(b - CHROMA_KEY_RGB[2]) < 25
  );
}

export function isSeparatorPixel(r: number, g: number, b: number): boolean {
  return (r > 180 && b > 180 && g < 100) || (r > 200 && b > 200 && g < 80);
}

export function isChromaOrSeparator(r: number, g: number, b: number): boolean {
  return isChromaKeyPixel(r, g, b) || isSeparatorPixel(r, g, b);
}

/** Zero alpha for chroma-key gray and magenta seam pixels in-place. */
export function applyChromaKeyInPlace(raw: Buffer, width: number, height: number): void {
  const pixels = width * height;
  for (let i = 0; i < pixels; i++) {
    const o = i * 4;
    if (isChromaOrSeparator(raw[o], raw[o + 1], raw[o + 2])) {
      raw[o + 3] = 0;
    }
  }
}

/**
 * Bounding box of the largest 4-connected opaque component (alpha > threshold).
 * Avoids picking seam glow fragments over the main subject.
 */
export function getLargestOpaqueBBox(
  raw: Buffer,
  width: number,
  height: number,
  alphaThreshold: number = 15,
): BBox | null {
  const pixels = width * height;
  const mask = new Uint8Array(pixels);
  for (let i = 0; i < pixels; i++) {
    if (raw[i * 4 + 3] > alphaThreshold) {
      mask[i] = 1;
    }
  }

  const labels = new Int32Array(pixels);
  let currentLabel = 0;
  const componentSizes = new Map<number, number>();
  const componentBounds = new Map<number, { minX: number; maxX: number; minY: number; maxY: number }>();

  const stack: number[] = [];

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;
      if (mask[idx] === 0 || labels[idx] !== 0) continue;

      currentLabel++;
      let size = 0;
      let minX = x;
      let maxX = x;
      let minY = y;
      let maxY = y;

      stack.push(idx);
      labels[idx] = currentLabel;

      while (stack.length > 0) {
        const cur = stack.pop()!;
        size++;
        const cx = cur % width;
        const cy = Math.floor(cur / width);
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;

        const neighbors = [
          cur - 1,
          cur + 1,
          cur - width,
          cur + width,
        ];
        for (const n of neighbors) {
          const nx = n % width;
          const ny = Math.floor(n / width);
          if (n < 0 || n >= pixels) continue;
          if (Math.abs(nx - cx) + Math.abs(ny - cy) !== 1) continue;
          if (mask[n] === 0 || labels[n] !== 0) continue;
          labels[n] = currentLabel;
          stack.push(n);
        }
      }

      componentSizes.set(currentLabel, size);
      componentBounds.set(currentLabel, { minX, maxX, minY, maxY });
    }
  }

  if (componentSizes.size === 0) {
    return null;
  }

  let bestLabel = 0;
  let bestSize = 0;
  for (const [label, size] of componentSizes) {
    if (size > bestSize) {
      bestSize = size;
      bestLabel = label;
    }
  }

  const bounds = componentBounds.get(bestLabel)!;
  return {
    left: bounds.minX,
    top: bounds.minY,
    width: bounds.maxX - bounds.minX + 1,
    height: bounds.maxY - bounds.minY + 1,
  };
}

/** Apply chroma-key to a sheet image file; writes PNG and returns buffer. */
export async function chromaKeyImageFile(inputPath: string, outputPath: string): Promise<Buffer> {
  const image = sharp(inputPath);
  const meta = await image.metadata();
  const w = meta.width!;
  const h = meta.height!;
  const raw = Buffer.from(await image.ensureAlpha().raw().toBuffer());

  applyChromaKeyInPlace(raw, w, h);

  const buf = await sharp(raw, { raw: { width: w, height: h, channels: 4 } }).png().toBuffer();
  fs.writeFileSync(outputPath, buf);
  return buf;
}
