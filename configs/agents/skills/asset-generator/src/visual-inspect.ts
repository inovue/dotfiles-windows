import sharp from 'sharp';

export interface CellVisualMetrics {
  magentaBorderRatio: number;
  aspectRatio: number;
  maxSide: number;
  minSide: number;
}

export function isMagentaLike(r: number, g: number, b: number): boolean {
  return r > 180 && b > 180 && g < 100;
}

/** Fraction of opaque border pixels that look like magenta seam residue. */
export async function measureBorderMagentaRatio(
  imageBuffer: Buffer,
  borderPx: number = 2,
): Promise<number> {
  const meta = await sharp(imageBuffer).metadata();
  const w = meta.width!;
  const h = meta.height!;
  if (w < 4 || h < 4) return 0;

  const raw = await sharp(imageBuffer).ensureAlpha().raw().toBuffer();
  let magenta = 0;
  let total = 0;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const onBorder = x < borderPx || x >= w - borderPx || y < borderPx || y >= h - borderPx;
      if (!onBorder) continue;
      const i = (y * w + x) * 4;
      if (raw[i + 3] <= 15) continue;
      total++;
      if (isMagentaLike(raw[i], raw[i + 1], raw[i + 2])) magenta++;
    }
  }

  return total === 0 ? 0 : magenta / total;
}

export async function measureCellVisuals(imageBuffer: Buffer): Promise<CellVisualMetrics> {
  const meta = await sharp(imageBuffer).metadata();
  const w = meta.width ?? 1;
  const h = meta.height ?? 1;
  const maxSide = Math.max(w, h);
  const minSide = Math.min(w, h);
  const magentaBorderRatio = await measureBorderMagentaRatio(imageBuffer);
  return {
    magentaBorderRatio,
    aspectRatio: maxSide / Math.max(1, minSide),
    maxSide,
    minSide,
  };
}

export function scoreVisualHeuristics(
  issues: { level: 'error' | 'warn' }[],
): number {
  let score = 15;
  for (const issue of issues) {
    score -= issue.level === 'error' ? 8 : 3;
  }
  return Math.max(0, score);
}
