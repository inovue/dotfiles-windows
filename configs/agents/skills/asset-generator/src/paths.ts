import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';

export function getTodayDateString(): string {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

export function generateBatchId(): string {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  let id = '';
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return `asset_${id}`;
}

export function resolveDefaultOutputDir(batchId: string): string {
  const dateStr = getTodayDateString();
  const picturesDir = path.join(os.homedir(), 'Pictures', 'assets', dateStr, batchId);
  return picturesDir;
}

export function parseOutPath(rawPath?: string, batchId?: string): { outDir: string; customFilename?: string } {
  const id = batchId || generateBatchId();
  if (!rawPath) {
    return { outDir: resolveDefaultOutputDir(id) };
  }

  const resolved = path.isAbsolute(rawPath) ? rawPath : path.resolve(process.cwd(), rawPath);
  const ext = path.extname(resolved).toLowerCase();

  // If path ends with an image extension, split into dir and custom filename
  if (['.webp', '.png', '.jpg', '.jpeg'].includes(ext)) {
    return {
      outDir: path.dirname(resolved),
      customFilename: path.basename(resolved),
    };
  }

  return { outDir: resolved };
}

/** Normalized absolute output dir for confirm-token binding when user passes -o. */
export function resolveDigestOutDir(rawOut?: string): string | undefined {
  if (!rawOut?.trim()) return undefined;
  const { outDir } = parseOutPath(rawOut.trim(), 'digest_bind');
  return path.resolve(outDir).replace(/\\/g, '/');
}

export function ensureDirSync(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}
