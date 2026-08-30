export type GridSize = '1' | '4' | '9' | '16' | '1x1' | '2x2' | '3x3' | '4x4';

export type AspectRatio = '1:1' | '16:9' | '9:16' | '4:3' | '3:4' | '3:2' | '2:3' | '21:9';

export type OutputFormat = 'webp' | 'png' | 'jpeg';

export type CompositionLayout = 'centered' | 'right-heavy' | 'left-heavy' | 'wide-isometric' | 'floating-elements';

export type ReferenceMode = 'character' | 'style' | 'auto';

export interface CellSpec {
  id?: string;
  prompt: string;
}

export type ModelQuality = 'low' | 'medium' | 'high';

export interface StylePreset {
  id: string;
  name: string;
  aliases: string[];
  description: string;
  promptSuffix: string;
  negativePrompt?: string;
}

export interface GridBand {
  index: number;
  row: number;
  col: number;
  left: number;
  top: number;
  width: number;
  height: number;
  label?: string;
}

export interface GridMeta {
  version: 1;
  cols: number;
  rows: number;
  srcSize: [number, number];
  keyColor: string;
  separatorColor: string;
  bands: GridBand[];
  colSeams: number[];
  rowSeams: number[];
  detector: 'magenta' | 'weak-magenta' | 'profile' | 'equal-split';
  seamConfidence?: { col: number[]; row: number[] };
  magentaSeamHits?: number;
  totalSeams?: number;
}

export interface AssetManifestItem {
  id: string;
  cellId?: string;
  filename: string;
  index: number;
  row?: number;
  col?: number;
  label: string;
  /** Opaque-pixel ratio on the RGBA buffer before final encode (not meaningful on JPEG files). */
  alphaCoverage?: number;
  width: number;
  height: number;
  path: string;            // Absolute path
  relativePath: string;    // Relative path from project root (e.g. src/assets/...)
  astroImportPath: string; // Ready-to-use Astro path (e.g. "@/assets/images/...")
}

export interface ManifestQuality {
  gridDetector?: GridMeta['detector'];
  seamConfidence?: { col: number[]; row: number[] };
  magentaSeamHits?: number;
  totalSeams?: number;
  alphaGateMin: number;
  minAlphaCoverage?: number;
  minWidth?: number;
  minHeight?: number;
  dimensionGateMin?: number;
  cellsPassed: number;
}

export interface AssetManifest {
  version: 1;
  batchId: string;
  createdAt: string;
  mode: 'grid' | 'single';
  grid?: string;
  aspectRatio: string;
  style?: string;
  prompt: string;
  themePrompt?: string;
  itemsList?: string[];
  cellSpecs?: CellSpec[];
  confirmToken?: string;
  gridDetector?: GridMeta['detector'];
  quality?: ManifestQuality;
  modelQuality?: ModelQuality;
  preset?: 'logo' | 'icon' | 'wordmark';
  refImages?: string[];
  refMode?: ReferenceMode;
  padPercent?: number;
  /** Final cell file format after grid split (webp | png | jpeg). */
  outputFormat?: OutputFormat;
  /** Encoder quality 1–100 used for cell files. */
  encodingQuality?: number;
  /** Background used when flattening transparency for JPEG output. */
  jpegBackground?: string;
  items: AssetManifestItem[];
  files: {
    raw?: string;
    transparent?: string;
    gridMeta?: string;
  };
}

export interface GeneratorOptions {
  countOrGrid?: string;
  prompt: string;
  items?: string[];
  itemsRaw?: string;
  style?: string;
  aspect?: AspectRatio;
  composition?: CompositionLayout;
  modelQuality?: ModelQuality; // 'low' | 'medium' | 'high' (default: 'low')
  outDir?: string;
  /** Resolved -o directory included in confirm token when user passes -o */
  outDirResolved?: string;
  customFilename?: string;
  format?: OutputFormat;
  quality?: number; // Encoder quality 1–100 (default: 80)
  rembg?: boolean;
  refImages?: string[];      // Multiple reference image paths (up to 3)
  refMode?: ReferenceMode;   // 'character' | 'style' | 'auto'
  pad?: number;
  is2k?: boolean;
  size?: number;
  tight?: boolean;
  rawCell?: boolean;
  jsonOutput?: boolean;
  debug?: boolean;
  printPrompt?: boolean;
  confirmToken?: string;
  allowWeakSeams?: boolean;
  allowEmptyCells?: boolean;
  preset?: 'logo' | 'icon' | 'wordmark';
  grillAck?: string;
  skipGrillAck?: boolean;
  allowJpegLogos?: boolean;
  inspectDir?: string;
}
