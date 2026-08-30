import { parseCellSpecs, validateGenerationGate, validateGridCells, computeBatchDigest, computeGrillAckToken } from './items.js';
import { DEFAULT_ENCODING_QUALITY, normalizeCustomFilename, resolveOutputFormat } from './format.js';
import { resolveDigestOutDir } from './paths.js';
import { resolveStyle } from './presets.js';
import { PipelineValidationError } from './validate.js';
import type { CellSpec, CompositionLayout, GeneratorOptions, ReferenceMode } from './types.js';

export const CHROMA_KEY_HEX = '#C0C0C0';
export const SEPARATOR_HEX = '#FF00FF';

const COMPOSITION_PROMPTS: Record<CompositionLayout, string> = {
  'centered': 'Composition: Balanced symmetrical composition, primary subject perfectly centered with clean negative space around edges.',
  'right-heavy': 'Composition: UI-friendly layout. Primary focal subject is positioned in the right half of the canvas, leaving clean open negative space on the left half for headline and CTA text placement.',
  'left-heavy': 'Composition: UI-friendly layout. Primary focal subject is positioned in the left half of the canvas, leaving clean open negative space on the right half for copy placement.',
  'wide-isometric': 'Composition: Wide-angle technical isometric perspective, cinematic breadth, modular components arranged along a clean diagonal plane.',
  'floating-elements': 'Composition: Dynamic floating elements composition, central main artifact surrounded by subtle hovering accent badges, icons, and micro-particles with shallow depth of field.',
};

const REF_MODE_PROMPTS: Record<ReferenceMode, string> = {
  'character': 'Reference Image Usage: Strictly maintain the exact character / mascot identity, facial features, proportions, color palette, costume, and visual design from the reference image(s). Render this exact same character performing the specific actions, poses, and expressions described in each grid cell.',
  'style': 'Reference Image Usage: Extract and strictly replicate the exact artistic rendering style, material textures, brush strokes, shading, lighting, and aesthetic palette from the reference image(s). Render the new objects described below in this exact visual aesthetic.',
  'auto': 'Reference Image Usage: Use the provided reference image(s) as visual anchoring for visual style, color palette, and subject identity as contextually requested.',
};

export function parseGridCount(input?: string): { cols: number; rows: number; total: number } {
  if (!input) return { cols: 1, rows: 1, total: 1 };
  const v = input.trim().toLowerCase();
  if (v === '1' || v === '1x1' || v === 'single') return { cols: 1, rows: 1, total: 1 };
  if (v === '4' || v === '2x2') return { cols: 2, rows: 2, total: 4 };
  if (v === '9' || v === '3x3') return { cols: 3, rows: 3, total: 9 };
  if (v === '16' || v === '4x4') return { cols: 4, rows: 4, total: 16 };

  const m = /^(\d+)x(\d+)$/i.exec(v);
  if (m) {
    const c = parseInt(m[1], 10);
    const r = parseInt(m[2], 10);
    return { cols: c, rows: r, total: c * r };
  }
  return { cols: 1, rows: 1, total: 1 };
}

export { parseCellSpecs, validateGridCells, validateGenerationGate, computeBatchDigest };

export function getCellShapeHint(cols: number, rows: number): string | null {
  if (cols === 1 && rows === 1) return null;
  if (cols > rows) {
    return 'Cell Shape: Each grid cell is wider than tall (landscape). Design horizontal wordmarks, wide logos, and left-to-right typographic lockups that fill the cell width. Keep vertical margins inside the cell; do not stretch into magenta dividers.';
  }
  if (rows > cols) {
    return 'Cell Shape: Each grid cell is taller than wide (portrait). Design vertical badges, stacked logotypes, and tall icons centered in the cell.';
  }
  return 'Cell Shape: Square cells. Center each subject with balanced padding on all sides.';
}

export function buildPrompt(options: GeneratorOptions): {
  prompt: string;
  gridInfo: { cols: number; rows: number; total: number };
  itemsList: string[];
  cellSpecs: CellSpec[];
  confirmToken: string;
  grillAckToken: string;
} {
  const gridInfo = parseGridCount(options.countOrGrid);
  const style = resolveStyle(options.style);
  const cellSpecs = parseCellSpecs(options.items, options.itemsRaw);
  validateGridCells(cellSpecs, gridInfo.total);

  options.format = resolveOutputFormat(options.format, options.customFilename);
  if (options.customFilename) {
    options.customFilename = normalizeCustomFilename(options.customFilename, options.format);
  }
  if (options.quality == null) {
    options.quality = DEFAULT_ENCODING_QUALITY;
  }

  if (!options.outDirResolved && options.outDir) {
    options.outDirResolved = resolveDigestOutDir(options.outDir);
  }

  if (
    options.format === 'jpeg' &&
    (options.preset === 'logo' || options.preset === 'wordmark') &&
    !options.allowJpegLogos
  ) {
    throw new PipelineValidationError(
      'JPEG output is blocked for --preset logo/wordmark (transparency is flattened to white).\n' +
        'Use -f webp or -f png, or pass --allow-jpeg-logos to override.',
    );
  }

  const themePrompt = options.prompt.trim() || 'UI Asset Collection';
  const confirmToken = computeBatchDigest(gridInfo.total, themePrompt, cellSpecs, options);
  const grillAckToken = computeGrillAckToken(confirmToken);
  const gateMode = gridInfo.total > 1 ? 'grid' : 'single';
  validateGenerationGate(options, confirmToken, gateMode);

  const itemsList = cellSpecs.map((c) => c.prompt);
  const refMode = options.refMode || (options.refImages && options.refImages.length > 0 ? 'auto' : undefined);

  if (gridInfo.total === 1) {
    let p = cellSpecs[0]?.prompt || themePrompt;

    if (refMode && REF_MODE_PROMPTS[refMode]) {
      p += `\n\n${REF_MODE_PROMPTS[refMode]}`;
    }

    if (options.composition && COMPOSITION_PROMPTS[options.composition]) {
      p += `\n\n${COMPOSITION_PROMPTS[options.composition]}`;
    }

    if (style) {
      p += `\n\nVisual Art Style: ${style.promptSuffix}`;
    }

    return { prompt: p, gridInfo, itemsList, cellSpecs, confirmToken, grillAckToken };
  }

  let p = `A neat ${gridInfo.rows}x${gridInfo.cols} grid sprite sheet containing exactly ${gridInfo.total} distinct isolated assets.\n`;
  p += `Layout Structure: Strictly ${gridInfo.rows} rows and ${gridInfo.cols} columns.\n`;
  p += `Background: Uniform solid flat neutral gray ${CHROMA_KEY_HEX} across the entire background.\n`;
  p += `Dividing Grid Lines: Thin, clear, continuous solid magenta ${SEPARATOR_HEX} separator lines drawn between all rows and columns.\n`;
  p += `Each asset must be completely centered inside its own cell and must not touch or cross the ${SEPARATOR_HEX} divider lines.\n`;

  const shapeHint = getCellShapeHint(gridInfo.cols, gridInfo.rows);
  if (shapeHint) {
    p += `${shapeHint}\n`;
  }
  if (options.preset === 'wordmark' || options.preset === 'logo') {
    p += 'Subject Framing: High-contrast logo/wordmark with clean edges. Avoid full-bleed glow touching cell borders. Text must be fully legible.\n';
    p += 'Typography rule: Wordmark cells must render readable spelled-out English text. Never replace a text cell with icons, shields, charts, or single-letter monograms unless the cell prompt explicitly asks for an icon.\n';
  }
  p += '\n';

  if (refMode && REF_MODE_PROMPTS[refMode]) {
    p += `${REF_MODE_PROMPTS[refMode]}\n\n`;
  }

  if (style) {
    p += `Art Style: ${style.promptSuffix}\n\n`;
  }

  p += `Theme / Context: ${themePrompt}\n\n`;

  p += `Individual Cell Contents (Ultra-Detailed Specifications):\n`;
  for (let i = 0; i < gridInfo.total; i++) {
    const r = Math.floor(i / gridInfo.cols) + 1;
    const c = (i % gridInfo.cols) + 1;
    p += `- [Row ${r}, Col ${c}]: ${cellSpecs[i].prompt}\n`;
  }

  return { prompt: p, gridInfo, itemsList, cellSpecs, confirmToken, grillAckToken };
}
