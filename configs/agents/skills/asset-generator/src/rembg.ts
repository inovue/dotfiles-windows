import { fal } from '@fal-ai/client';
import fs from 'node:fs';
import { basename } from 'node:path';
import sharp from 'sharp';
import { downloadFile, requireFalKey, withRetry } from './fal.js';

export const PIXELCUT_MODEL = 'pixelcut/background-removal';
export const BIREFNET_MODEL = 'fal-ai/birefnet';

export async function removeBackground(
  imagePath: string,
  destPath: string,
): Promise<string> {
  const key = requireFalKey();
  fal.config({ credentials: key });

  const fileData = fs.readFileSync(imagePath);
  const fileName = basename(imagePath);
  const fileObj = new File([fileData], fileName, { type: 'image/png' });

  console.log('\x1b[36m⚡ Uploading sheet to fal.ai storage...\x1b[0m');
  const imageUrl = await fal.storage.upload(fileObj);

  console.log(`\x1b[36m⚡ Removing background via fal.ai (${PIXELCUT_MODEL})...\x1b[0m`);

  try {
    await withRetry(async () => {
      const result = await fal.subscribe(PIXELCUT_MODEL, {
        input: {
          image_url: imageUrl,
          output_format: 'rgba',
        },
        logs: false,
      });

      const image = (result.data as any)?.image;
      if (!image?.url) {
        throw new Error('Background removal failed: no image URL returned');
      }

      await downloadFile(image.url, destPath);
    }, `Background Removal (${PIXELCUT_MODEL})`);
  } catch (err: any) {
    console.warn(`\x1b[33m[WARN] ${PIXELCUT_MODEL} failed, trying fallback to ${BIREFNET_MODEL}...\x1b[0m`);
    await withRetry(async () => {
      const result = await fal.subscribe(BIREFNET_MODEL, {
        input: {
          image_url: imageUrl,
        },
        logs: false,
      });

      const image = (result.data as any)?.image;
      if (!image?.url) {
        throw new Error('Fallback background removal failed: no image URL returned');
      }

      await downloadFile(image.url, destPath);
    }, `Background Removal Fallback (${BIREFNET_MODEL})`);
  }

  // Ensure dimension matches original source
  const srcMeta = await sharp(imagePath).metadata();
  const destMeta = await sharp(destPath).metadata();
  if (srcMeta.width && srcMeta.height && (destMeta.width !== srcMeta.width || destMeta.height !== srcMeta.height)) {
    const tempDest = destPath + '.tmp.png';
    fs.copyFileSync(destPath, tempDest);
    await sharp(tempDest)
      .ensureAlpha()
      .resize(srcMeta.width, srcMeta.height, { fit: 'fill' })
      .png()
      .toFile(destPath);
    fs.unlinkSync(tempDest);
  }

  return destPath;
}
