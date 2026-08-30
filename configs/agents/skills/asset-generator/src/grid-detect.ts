import sharp from "sharp";
import { CHROMA_KEY_HEX, SEPARATOR_HEX } from "./prompt.js";
import type { GridBand, GridMeta } from "./types.js";

export const SEPARATOR_RGB: [number, number, number] = [255, 0, 255];
export const MAGENTA_SEAM_THRESHOLD = 0.05;

function rgbDist(r1: number, g1: number, b1: number, r2: number, g2: number, b2: number): number {
  return Math.sqrt((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2);
}

export function isMagentaPixel(r: number, g: number, b: number): boolean {
  return (r > 180 && b > 180 && g < 100) || rgbDist(r, g, b, 255, 0, 255) < 95;
}

function findSeam(
  scores: Float32Array,
  center: number,
  window: number,
  maxBound: number,
): { index: number; confidence: number; usedMagenta: boolean } {
  const start = Math.max(0, center - window);
  const end = Math.min(maxBound - 1, center + window);

  let maxVal = -1;
  let maxIdx = center;
  for (let i = start; i <= end; i++) {
    if (scores[i] > maxVal) {
      maxVal = scores[i];
      maxIdx = i;
    }
  }

  const usedMagenta = maxVal > MAGENTA_SEAM_THRESHOLD;
  return {
    index: usedMagenta ? maxIdx : center,
    confidence: Math.max(0, maxVal),
    usedMagenta,
  };
}

export async function detectGridSeams(
  imagePath: string,
  cols: number,
  rows: number,
): Promise<GridMeta> {
  const image = sharp(imagePath);
  const metadata = await image.metadata();
  const width = metadata.width || 1024;
  const height = metadata.height || 1024;

  if (cols === 1 && rows === 1) {
    const singleBand: GridBand = {
      index: 0,
      row: 0,
      col: 0,
      left: 0,
      top: 0,
      width,
      height,
    };
    return {
      version: 1,
      cols: 1,
      rows: 1,
      srcSize: [width, height],
      keyColor: CHROMA_KEY_HEX,
      separatorColor: SEPARATOR_HEX,
      bands: [singleBand],
      colSeams: [],
      rowSeams: [],
      detector: "equal-split",
    };
  }

  const rawBuffer = await image.raw().toBuffer();
  const channels = metadata.channels || 3;

  const colScores = new Float32Array(width);
  for (let x = 0; x < width; x++) {
    let magentaCount = 0;
    for (let y = 0; y < height; y++) {
      const idx = (y * width + x) * channels;
      if (isMagentaPixel(rawBuffer[idx], rawBuffer[idx + 1], rawBuffer[idx + 2])) {
        magentaCount++;
      }
    }
    colScores[x] = magentaCount / height;
  }

  const rowScores = new Float32Array(height);
  for (let y = 0; y < height; y++) {
    let magentaCount = 0;
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * channels;
      if (isMagentaPixel(rawBuffer[idx], rawBuffer[idx + 1], rawBuffer[idx + 2])) {
        magentaCount++;
      }
    }
    rowScores[y] = magentaCount / width;
  }

  const colSeams: number[] = [];
  const rowSeams: number[] = [];
  const colConfidence: number[] = [];
  const rowConfidence: number[] = [];
  let magentaHits = 0;
  let totalSeams = 0;

  const expectedColStep = width / cols;
  for (let c = 1; c < cols; c++) {
    const center = Math.round(c * expectedColStep);
    const window = Math.round(expectedColStep * 0.25);
    const seam = findSeam(colScores, center, window, width);
    colSeams.push(seam.index);
    colConfidence.push(seam.confidence);
    totalSeams++;
    if (seam.usedMagenta) magentaHits++;
  }

  const expectedRowStep = height / rows;
  for (let r = 1; r < rows; r++) {
    const center = Math.round(r * expectedRowStep);
    const window = Math.round(expectedRowStep * 0.25);
    const seam = findSeam(rowScores, center, window, height);
    rowSeams.push(seam.index);
    rowConfidence.push(seam.confidence);
    totalSeams++;
    if (seam.usedMagenta) magentaHits++;
  }

  const bands: GridBand[] = [];
  const colBounds = [0, ...colSeams, width];
  const rowBounds = [0, ...rowSeams, height];

  let idx = 0;
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const left = colBounds[c];
      const right = colBounds[c + 1];
      const top = rowBounds[r];
      const bottom = rowBounds[r + 1];

      bands.push({
        index: idx++,
        row: r,
        col: c,
        left,
        top,
        width: Math.max(1, right - left),
        height: Math.max(1, bottom - top),
      });
    }
  }

  let detector: GridMeta['detector'];
  if (magentaHits === totalSeams) {
    detector = 'magenta';
  } else if (magentaHits === 0) {
    detector = 'equal-split';
  } else {
    detector = 'weak-magenta';
  }

  return {
    version: 1,
    cols,
    rows,
    srcSize: [width, height],
    keyColor: CHROMA_KEY_HEX,
    separatorColor: SEPARATOR_HEX,
    bands,
    colSeams,
    rowSeams,
    detector,
    seamConfidence: { col: colConfidence, row: rowConfidence },
    magentaSeamHits: magentaHits,
    totalSeams,
  };
}
