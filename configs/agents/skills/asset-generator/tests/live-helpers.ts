import fs from 'node:fs';
import path from 'node:path';
import type { GeneratorOptions } from '../src/types.js';
import { buildPrompt } from '../src/prompt.js';
import { runAssetGenerator } from '../src/engine.js';
import { inspectBatch, type InspectResult } from '../src/inspect.js';
import { computeGrillAckToken } from '../src/digest.js';

export interface LiveRunResult {
  outDir: string;
  inspection: InspectResult;
}

export async function runLiveBatch(
  baseOptions: GeneratorOptions & { outDir: string },
  options: { allowWeakSeams?: boolean; clean?: boolean } = {},
): Promise<LiveRunResult> {
  const outDir = path.resolve(baseOptions.outDir);
  if (options.clean !== false && fs.existsSync(outDir)) {
    fs.rmSync(outDir, { recursive: true, force: true });
  }

  const dry = buildPrompt({ ...baseOptions, printPrompt: true });
  await runAssetGenerator({
    ...baseOptions,
    outDir,
    printPrompt: false,
    confirmToken: dry.confirmToken,
    grillAck: computeGrillAckToken(dry.confirmToken),
    allowWeakSeams: options.allowWeakSeams ?? false,
  });

  const inspection = await inspectBatch(outDir, {
    allowWeakSeams: options.allowWeakSeams ?? false,
  });

  return { outDir, inspection };
}

export function summarizeStability(runs: InspectResult[]): {
  technicalScores: number[];
  totalScores: number[];
  detectors: string[];
  spread: number;
  minTechnical: number;
  maxTechnical: number;
} {
  const technicalScores = runs.map((r) => r.breakdown.technicalScore);
  const totalScores = runs.map((r) => r.breakdown.total);
  const detectors = runs.map(
    (r) => r.gridMeta?.detector ?? r.manifest?.quality?.gridDetector ?? r.manifest?.gridDetector ?? 'unknown',
  );
  const minTechnical = Math.min(...technicalScores);
  const maxTechnical = Math.max(...technicalScores);
  return {
    technicalScores,
    totalScores,
    detectors,
    spread: maxTechnical - minTechnical,
    minTechnical,
    maxTechnical,
  };
}
