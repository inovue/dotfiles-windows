import fs from 'node:fs';
import path from 'node:path';
import { computeBatchDigest, computeGrillAckToken } from './digest.js';

export class ItemsParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ItemsParseError';
  }
}

export interface CellSpec {
  id?: string;
  prompt: string;
}

/** Extract leading label id from "Cell A: ..." or "A: ..." patterns. */
export function extractLeadingId(text: string): string | undefined {
  const m = /^(?:Cell\s+)?([A-Za-z][A-Za-z0-9_-]*)\s*[:：]\s*/i.exec(text.trim());
  return m ? m[1].toLowerCase() : undefined;
}

function normalizeCellEntry(entry: unknown, index: number): CellSpec {
  if (typeof entry === 'string') {
    const prompt = entry.trim();
    if (!prompt) {
      throw new ItemsParseError(`cells[${index}] is empty.`);
    }
    return { id: extractLeadingId(prompt), prompt };
  }

  if (entry && typeof entry === 'object' && 'prompt' in entry) {
    const obj = entry as { id?: string; prompt: unknown };
    const prompt = String(obj.prompt ?? '').trim();
    if (!prompt) {
      throw new ItemsParseError(`cells[${index}].prompt is empty.`);
    }
    const id = obj.id?.trim() || extractLeadingId(prompt);
    return { id: id || undefined, prompt };
  }

  throw new ItemsParseError(
    `cells[${index}] must be a string or { "id": "slug", "prompt": "description" }.`,
  );
}

/** Resolve @path.json file references (Windows-safe; avoids shell quoting). */
export function resolveItemsRaw(itemsRaw: string, cwd: string = process.cwd()): string {
  let trimmed = itemsRaw.trim();

  // PowerShell eats bare @cells.json (splatting) — accept plain cells.json too
  if (!trimmed.startsWith('@') && !trimmed.startsWith('[') && /\.json$/i.test(trimmed)) {
    trimmed = `@${trimmed}`;
  }

  if (!trimmed.startsWith('@')) {
    return trimmed;
  }

  const filePath = trimmed.slice(1).trim();
  if (!filePath) {
    throw new ItemsParseError('--items @ requires a file path (e.g. --items @cells.json).');
  }

  const resolved = path.isAbsolute(filePath) ? filePath : path.resolve(cwd, filePath);
  if (!fs.existsSync(resolved)) {
    throw new ItemsParseError(`Items file not found: ${resolved}`);
  }

  return fs.readFileSync(resolved, 'utf-8').trim();
}

export function parseCellSpecs(
  rawItems: string[] | undefined,
  itemsRaw: string | undefined,
  cwd: string = process.cwd(),
): CellSpec[] {
  if (rawItems && rawItems.length > 0) {
    return rawItems.map((s, i) => normalizeCellEntry(s, i));
  }

  if (!itemsRaw) {
    return [];
  }

  const trimmedRaw = itemsRaw.trim();

  // Inline JSON on Windows is almost always broken by shell quoting — block it.
  if (trimmedRaw.startsWith('[') && process.platform === 'win32') {
    throw new ItemsParseError(
      'Inline --items JSON is blocked on Windows (PowerShell quoting breaks arrays).\n' +
        'Write cells.json and pass --items @cells.json instead.',
    );
  }

  const content = resolveItemsRaw(itemsRaw, cwd);

  if (content.startsWith('[')) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(content);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      throw new ItemsParseError(
        `--items JSON parse failed: ${msg}\n` +
          'Use --items @cells.json with a valid JSON array.',
      );
    }

    if (!Array.isArray(parsed)) {
      throw new ItemsParseError('--items JSON must be an array.');
    }

    if (parsed.length === 0) {
      throw new ItemsParseError('--items JSON array is empty.');
    }

    return parsed.map((entry, i) => normalizeCellEntry(entry, i));
  }

  const lines = content
    .split('\n')
    .map((s) => s.trim().replace(/^[-*\d.]+\s*/, ''))
    .filter(Boolean);

  if (lines.length > 0) {
    return lines.map((line, i) => normalizeCellEntry(line, i));
  }

  throw new ItemsParseError(
    '--items must be @cells.json, a JSON array, or newline-separated cell descriptions.',
  );
}

/** @deprecated Use parseCellSpecs — returns prompts only. */
export function parseItemsList(
  rawItems: string[] | undefined,
  itemsRaw: string | undefined,
  _gridTotal: number = 1,
  cwd: string = process.cwd(),
): string[] {
  return parseCellSpecs(rawItems, itemsRaw, cwd).map((c) => c.prompt);
}

export function validateGridCells(specs: CellSpec[], gridTotal: number): void {
  if (gridTotal <= 1) {
    return;
  }

  if (specs.length === 0) {
    throw new ItemsParseError(
      `Grid mode requires exactly ${gridTotal} cell descriptions.\n` +
        'Use --items @cells.json with a JSON array of strings or { "id", "prompt" } objects.',
    );
  }

  if (specs.length !== gridTotal) {
    throw new ItemsParseError(
      `Cell count mismatch: ${gridTotal}-cell grid but ${specs.length} item(s) provided.\n` +
        'Each array element must be one complete cell — commas inside a cell are allowed.',
    );
  }
}

/** @deprecated Use validateGridCells */
export function validateGridItems(itemsList: string[], gridTotal: number): void {
  validateGridCells(
    itemsList.map((prompt) => ({ prompt })),
    gridTotal,
  );
}

export function validateGenerationGate(
  options: { printPrompt?: boolean; confirmToken?: string; grillAck?: string; skipGrillAck?: boolean },
  expectedToken: string,
  mode: 'grid' | 'single' = 'grid',
): void {
  if (options.printPrompt) {
    return;
  }

  if (!options.confirmToken) {
    throw new ItemsParseError(
      `${mode === 'grid' ? 'Grid' : 'Generation'} blocked: missing --confirm <token>.\n` +
        'Run --print-prompt first; copy the CONFIRM TOKEN from output.',
    );
  }

  if (options.confirmToken !== expectedToken) {
    throw new ItemsParseError(
      `Confirm token mismatch (got "${options.confirmToken}", expected "${expectedToken}").\n` +
        'Inputs or flags changed since dry-run — re-run --print-prompt.',
    );
  }

  if (options.skipGrillAck) {
    return;
  }

  const expectedGrill = computeGrillAckToken(expectedToken);
  if (!options.grillAck) {
    throw new ItemsParseError(
      'Generation blocked: missing --grill-ack <token>.\n' +
        'Complete GRILL CHECKLIST from --print-prompt, then pass GRILL_ACK token.',
    );
  }
  if (options.grillAck !== expectedGrill) {
    throw new ItemsParseError(
      `Grill ack mismatch (got "${options.grillAck}", expected "${expectedGrill}").\n` +
        'Re-run --print-prompt and copy GRILL_ACK after checklist review.',
    );
  }
}

export { computeBatchDigest, computeGrillAckToken };
