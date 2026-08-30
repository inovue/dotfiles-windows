import { fal } from '@fal-ai/client';
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import type { AspectRatio, GeneratorOptions, ResolutionTier } from './types.js';
import {
  DEFAULT_MODEL_QUALITY,
  DEFAULT_RESOLUTION_TIER,
  resolveResolutionTier,
} from './types.js';

export const GPT_IMAGE_GENERATE_MODEL = 'openai/gpt-image-2';
export const GPT_IMAGE_EDIT_MODEL = 'openai/gpt-image-2/edit';
export const MAX_REFERENCE_IMAGES = 3;
export const MAX_RETRIES = 3;

export function requireFalKey(): string {
  let key = process.env.FAL_KEY?.trim();
  if (!key && process.platform === 'win32') {
    try {
      const out = execSync(
        'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "[System.Environment]::GetEnvironmentVariable(\'FAL_KEY\', \'User\')"',
        { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }
      ).trim();
      if (out) {
        key = out;
        process.env.FAL_KEY = out;
      }
    } catch (_e) {
      // ignore
    }
  }

  if (!key) {
    throw new Error(
      '\x1b[31m[ERROR] FAL_KEY is not set.\x1b[0m\nPlease set your FAL_KEY environment variable (export FAL_KEY="your_api_key" or run `just setup-fal`).'
    );
  }
  return key;
}

export async function withRetry<T>(
  operation: () => Promise<T>,
  operationName: string,
  maxRetries: number = MAX_RETRIES
): Promise<T> {
  let attempt = 0;
  while (attempt < maxRetries) {
    try {
      return await operation();
    } catch (err: any) {
      attempt++;
      if (attempt >= maxRetries) {
        throw new Error(`${operationName} failed after ${maxRetries} attempts: ${err.message || err}`);
      }
      const delayMs = Math.pow(2, attempt) * 1000;
      console.warn(
        `\x1b[33m[WARN] ${operationName} failed (attempt ${attempt}/${maxRetries}). Retrying in ${delayMs / 1000}s... (${err.message || err})\x1b[0m`
      );
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  throw new Error(`${operationName} failed`);
}

/** Map aspect + resolution tier to fal.ai image_size (1K presets or 2K custom). */
export function aspectToFalSize(
  aspect?: AspectRatio,
  tier: ResolutionTier = DEFAULT_RESOLUTION_TIER,
): string | { width: number; height: number } {
  if (tier === '2k') {
    if (!aspect || aspect === '1:1') {
      return { width: 2048, height: 2048 };
    }
  }
  switch (aspect) {
    case '16:9': return 'landscape_16_9';
    case '9:16': return 'portrait_16_9';
    case '4:3': return 'landscape_4_3';
    case '3:4': return 'portrait_4_3';
    case '1:1':
    default:
      return tier === '2k' ? { width: 2048, height: 2048 } : 'square_hd';
  }
}

export async function downloadFile(url: string, destPath: string): Promise<void> {
  const res = await fetch(url);
  if (!res.ok || !res.body) {
    throw new Error(`Failed to download image from ${url}: ${res.statusText}`);
  }
  const fileStream = fs.createWriteStream(destPath);
  await pipeline(Readable.fromWeb(res.body as any), fileStream);
}

function fileToDataUrl(filePath: string): string {
  const buffer = fs.readFileSync(filePath);
  const ext = filePath.toLowerCase();
  const mime = ext.endsWith('.png') ? 'image/png' : ext.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
  return `data:${mime};base64,${buffer.toString('base64')}`;
}

/** Build fal.ai request payload (exported for unit tests). */
export function buildFalImageInput(
  prompt: string,
  options: GeneratorOptions,
): { modelId: string; input: Record<string, unknown>; refCount: number; tier: ResolutionTier } {
  const tier = resolveResolutionTier(options.is2k);
  const imageSize = aspectToFalSize(options.aspect, tier);
  const refImages = (options.refImages || []).filter((p) => fs.existsSync(p)).slice(0, MAX_REFERENCE_IMAGES);
  const hasRefs = refImages.length > 0;

  const modelId = hasRefs ? GPT_IMAGE_EDIT_MODEL : GPT_IMAGE_GENERATE_MODEL;
  const quality = options.modelQuality || DEFAULT_MODEL_QUALITY;

  const input: Record<string, unknown> = {
    prompt,
    image_size: imageSize,
    quality,
    num_images: 1,
    output_format: 'png',
  };

  if (hasRefs) {
    // gpt-image-2/edit requires image_urls (array); image_url alone returns 422.
    const urls = refImages.map(fileToDataUrl);
    input.image_urls = urls;
    input.image_url = urls[0];
  }

  return { modelId, input, refCount: refImages.length, tier };
}

export async function generateFalImage(
  prompt: string,
  destPath: string,
  options: GeneratorOptions,
): Promise<string> {
  const key = requireFalKey();
  fal.config({ credentials: key });

  const { modelId, input, refCount, tier } = buildFalImageInput(prompt, options);
  const quality = (input.quality as string) || DEFAULT_MODEL_QUALITY;

  if (refCount > 0) {
    console.log(`\x1b[36m📎 Attached ${refCount} reference image(s) (Mode: ${options.refMode || 'auto'})\x1b[0m`);
  }

  console.log(`\x1b[36m⚡ Calling fal.ai (${modelId}, ${tier.toUpperCase()}, quality: ${quality})...\x1b[0m`);

  await withRetry(async () => {
    const result = await fal.subscribe(modelId, {
      input,
      logs: false,
    });

    const images = (result.data as any)?.images;
    if (!images || images.length === 0 || !images[0]?.url) {
      throw new Error('fal.ai returned no valid image URLs in response');
    }

    const url = images[0].url;
    await downloadFile(url, destPath);
  }, `Image Generation (${modelId})`);

  return destPath;
}
