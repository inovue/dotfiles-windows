import sharp from 'sharp';
import type { GridMeta } from './types.js';

export class PipelineValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PipelineValidationError';
  }
}

export function validateGridSeams(
  gridMeta: GridMeta,
  options: { allowWeakSeams?: boolean } = {},
): void {
  if (gridMeta.cols === 1 && gridMeta.rows === 1) {
    return;
  }

  if (gridMeta.detector === 'magenta') {
    return;
  }

  if (options.allowWeakSeams) {
    return;
  }

  const conf = gridMeta.seamConfidence;
  const detail = conf
    ? `col=[${conf.col.map((v) => v.toFixed(2)).join(',')}] row=[${conf.row.map((v) => v.toFixed(2)).join(',')}]`
    : `detector=${gridMeta.detector}`;

  throw new PipelineValidationError(
    `Grid seam detection unreliable (${detail}).\n` +
      'The sheet likely lacks clear #FF00FF divider lines — cell boundaries may be wrong.\n' +
      'Re-generate with --mq high, or pass --allow-weak-seams to proceed anyway.',
  );
}

export async function measureAlphaCoverage(imageBuffer: Buffer): Promise<number> {
  const image = sharp(imageBuffer);
  const meta = await image.metadata();
  const w = meta.width!;
  const h = meta.height!;
  const raw = await image.ensureAlpha().raw().toBuffer();

  let opaque = 0;
  const total = w * h;
  for (let i = 0; i < total; i++) {
    if (raw[i * 4 + 3] > 15) opaque++;
  }
  return opaque / total;
}

export async function validateCellAlphaCoverage(
  imageBuffer: Buffer,
  label: string,
  index: number,
  options: { minCoverage?: number; allowEmptyCells?: boolean } = {},
): Promise<number> {
  const minCoverage = options.minCoverage ?? 0.02;
  const coverage = await measureAlphaCoverage(imageBuffer);

  if (!options.allowEmptyCells && coverage < minCoverage) {
    throw new PipelineValidationError(
      `Cell ${index + 1} (${label}) failed quality gate: ${(coverage * 100).toFixed(2)}% opaque pixels (min ${(minCoverage * 100).toFixed(0)}%).\n` +
        'Likely empty crop, rembg ate the subject, or bbox picked seam debris. Try --no-rembg --tight or re-generate.',
    );
  }

  return coverage;
}

export function validateCellDimensions(
  width: number,
  height: number,
  label: string,
  index: number,
  minPx: number = 32,
): void {
  if (width < minPx || height < minPx) {
    throw new PipelineValidationError(
      `Cell ${index + 1} (${label}) failed dimension gate: ${width}x${height}px (min ${minPx}px per side).\n` +
        'Crop too aggressive or seam misalignment — try --allow-weak-seams off and re-generate with --mq high.',
    );
  }
}
