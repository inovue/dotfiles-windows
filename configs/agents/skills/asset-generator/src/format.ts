import path from 'node:path';
import sharp from 'sharp';
import type { OutputFormat } from './types.js';

export const DEFAULT_ENCODING_QUALITY = 80;
export const JPEG_FLATTEN_BACKGROUND = '#ffffff';

const FORMAT_ALIASES: Record<string, OutputFormat> = {
  webp: 'webp',
  png: 'png',
  jpeg: 'jpeg',
  jpg: 'jpeg',
};

const EXTENSION_BY_FORMAT: Record<OutputFormat, string> = {
  webp: 'webp',
  png: 'png',
  jpeg: 'jpg',
};

/** Parse CLI / manifest format string; returns null when unrecognized. */
export function parseOutputFormat(raw: string | undefined): OutputFormat | null {
  if (!raw) return null;
  return FORMAT_ALIASES[raw.toLowerCase()] ?? null;
}

/** Map file extension (with or without dot) to output format. */
export function formatFromExtension(ext: string): OutputFormat | null {
  const normalized = ext.startsWith('.') ? ext.slice(1).toLowerCase() : ext.toLowerCase();
  if (normalized === 'webp') return 'webp';
  if (normalized === 'png') return 'png';
  if (normalized === 'jpg' || normalized === 'jpeg') return 'jpeg';
  return null;
}

export function clampEncodingQuality(quality: number): number {
  return Math.min(100, Math.max(1, Math.round(quality)));
}

/** Infer cell output format from a filename extension (legacy batches without manifest.outputFormat). */
export function inferOutputFormatFromFilename(filename: string): OutputFormat | null {
  return formatFromExtension(path.extname(filename));
}

/** sharp.metadata().format value for a given output format. */
export function sharpFormatForOutput(format: OutputFormat): string {
  return format === 'jpeg' ? 'jpeg' : format;
}

export function extensionForFormat(format: OutputFormat): string {
  return EXTENSION_BY_FORMAT[format];
}

/** Align -o filename extension with resolved output format when extension is a known image type. */
export function normalizeCustomFilename(filename: string, format: OutputFormat): string {
  const ext = path.extname(filename);
  if (!formatFromExtension(ext)) return filename;
  const stem = path.basename(filename, ext);
  return `${stem}.${extensionForFormat(format)}`;
}

/**
 * Resolve final cell output format: explicit -f wins, then -o filename extension, else webp.
 */
export function resolveOutputFormat(
  explicit?: string,
  customFilename?: string,
): OutputFormat {
  if (explicit) {
    const parsed = parseOutputFormat(explicit);
    if (!parsed) {
      throw new Error(
        `Invalid output format "${explicit}". Use webp, png, jpeg, or jpg.`,
      );
    }
    return parsed;
  }

  if (customFilename) {
    const inferred = formatFromExtension(path.extname(customFilename));
    if (inferred) return inferred;
  }

  return 'webp';
}

/** Encode a processed RGBA cell buffer to the requested final format. */
export async function encodeCellImage(
  rgbaBuffer: Buffer,
  format: OutputFormat,
  quality: number,
): Promise<Buffer> {
  const q = clampEncodingQuality(quality);
  let pipeline = sharp(rgbaBuffer).ensureAlpha();

  if (format === 'webp') {
    return pipeline
      .webp({ quality: q, alphaQuality: 90, nearLossless: true })
      .toBuffer();
  }

  if (format === 'png') {
    return pipeline.png({ quality: Math.min(100, q) }).toBuffer();
  }

  return pipeline
    .flatten({ background: { r: 255, g: 255, b: 255 } })
    .jpeg({ quality: q, mozjpeg: true })
    .toBuffer();
}
