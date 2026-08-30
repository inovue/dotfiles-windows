#!/usr/bin/env node
import { STYLE_PRESETS } from './presets.js';
import type { AspectRatio, CompositionLayout, GeneratorOptions, ModelQuality, ReferenceMode } from './types.js';
import { runAssetGenerator } from './engine.js';
import { ItemsParseError } from './items.js';
import { inspectBatch, formatInspectReport } from './inspect.js';
import { parseOutputFormat, clampEncodingQuality } from './format.js';
import { PipelineValidationError } from './validate.js';

function printHelp(): void {
  console.log(`
\x1b[1mAsset Generator CLI (Agent-Optimized LP Asset Pipeline)\x1b[0m

\x1b[33mUsage:\x1b[0m
  npx tsx <skill-dir>/src/cli.ts [options] [prompt]

\x1b[33mQuick Examples:\x1b[0m
  # Grid batch — use @cells.json on Windows (avoids PowerShell quoting bugs)
  cli.ts -g 4 "AI SaaS Core Features" -s clay -p 10 -o src/assets/images/features --items @cells.json

  # Logo preset (sets --mq high --tight)
  cli.ts --preset logo --confirm <token> -g 4 "Brand" --items cells.json -o out

  # Allow weak/missing magenta seams (not recommended)
  cli.ts --allow-weak-seams --confirm <token> -g 4 "Theme" --items cells.json

  # Character Mascot Reference (4 poses)
  cli.ts -g 4 "Mascot Feature Set" -r ./mascot.png -m character -s clay -o src/assets/images/features

  # Single Hero Visual with layout & filename target
  cli.ts "AI Workspace Platform" -s glass -a 16:9 -l right-heavy -o src/assets/images/hero.webp

\x1b[33mOptions (all support 1-letter flags):\x1b[0m
  -g, --grid <4|9|16|NxM>    Grid: 4 (2x2), 9 (3x3), 16 (4x4), 2x4, 1 (single)
  -s, --style <name>          Style preset (clay, glossy, glass, flat, iso, neon, badge, etc.)
  -a, --aspect <ratio>        Aspect ratio for 1-shot (1:1, 16:9, 9:16, 4:3, 3:2, 21:9)
  -l, --layout <name>         UI composition (right-heavy, left-heavy, centered, wide-isometric)
  -p, --pad <0-50>            Transparent padding % inside square canvas (default: 10)
  -r, --ref <path...>         Reference image(s) for character/style anchoring (max 3)
  -m, --ref-mode <mode>       Reference interpretation mode: character | style | auto (default: auto)
  --mq, --model-quality <q>   gpt-image-2 render quality: low (default) | medium | high
  -o, --out <path>            Output directory or specific image file path
  -f, --format <fmt>          Cell output format: webp (default) | png | jpeg | jpg
  -q, --quality <1-100>       Encoding quality for webp/png/jpeg (default: 80)
  -k, --2k                    Generate at 2048x2048 high resolution
  -j, --json                  Output machine-readable manifest JSON to stdout
  --size <px>                 Target output square size (e.g. 512, 256)
  --items <@file|json>        Cell specs: cells.json file (required for grids)
  --confirm <token>           Token from --print-prompt CONFIRM TOKEN line
  --grill-ack <token>         GRILL_ACK from --print-prompt (checklist completed)
  --preset <logo|wordmark|icon> logo/wordmark: --mq high --tight
  --allow-weak-seams          Proceed when magenta seam detection is unreliable
  --allow-empty-cells         Skip per-cell alpha coverage gate
  --tight                     Tight crop: chroma-key #C0C0C0/#FF00FF then largest subject bbox
  --raw-cell                  Keep raw cell bounds without trimming
  --no-rembg                  Disable background removal
  --allow-jpeg-logos          Allow -f jpeg with --preset logo/wordmark (flattened white bg)
  --print-prompt              Print the generated prompt and exit
  --inspect <dir>             Validate existing batch (manifest + files); no API call
  --list-styles               List all 14 available style presets
  -h, --help                  Show this help message
`);
}

function printStyles(): void {
  console.log('\x1b[1mAvailable Style Presets:\x1b[0m\n');
  for (const [id, preset] of Object.entries(STYLE_PRESETS)) {
    const aliasStr = preset.aliases.length > 0 ? ` (${preset.aliases.join(', ')})` : '';
    console.log(`  \x1b[36m${id}\x1b[0m${aliasStr}`);
    console.log(`    ${preset.name}: ${preset.description}\n`);
  }
}

export function parseArgs(args: string[]): GeneratorOptions {
  const options: GeneratorOptions = {
    prompt: '',
    rembg: true,
    refImages: [],
    modelQuality: 'low', // Default: 'low'
  };

  const positional: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '-h' || arg === '--help') {
      printHelp();
      process.exit(0);
    }
    if (arg === '--list-styles') {
      printStyles();
      process.exit(0);
    }
    if (arg === '--inspect') {
      options.inspectDir = args[++i];
      continue;
    }
    if (arg === '--allow-jpeg-logos') {
      options.allowJpegLogos = true;
      continue;
    }
    if (arg === '--print-prompt') {
      options.printPrompt = true;
      continue;
    }
    if (arg === '--grill-ack') {
      options.grillAck = args[++i];
      continue;
    }
    if (arg === '--skip-grill-ack') {
      options.skipGrillAck = true;
      continue;
    }
    if (arg === '--confirm') {
      options.confirmToken = args[++i];
      continue;
    }
    if (arg === '--allow-weak-seams') {
      options.allowWeakSeams = true;
      continue;
    }
    if (arg === '--allow-empty-cells') {
      options.allowEmptyCells = true;
      continue;
    }
    if (arg === '--preset') {
      const preset = args[++i]?.toLowerCase();
      if (preset === 'logo' || preset === 'wordmark') {
        options.preset = preset;
        options.modelQuality = 'high';
        options.tight = true;
      } else if (preset === 'icon') {
        options.preset = 'icon';
        options.modelQuality = 'medium';
      }
      continue;
    }
    if (arg === '-j' || arg === '--json') {
      options.jsonOutput = true;
      continue;
    }
    if (arg === '--no-rembg') {
      options.rembg = false;
      continue;
    }
    if (arg === '-k' || arg === '--2k') {
      options.is2k = true;
      continue;
    }
    if (arg === '--tight') {
      options.tight = true;
      continue;
    }
    if (arg === '--raw-cell') {
      options.rawCell = true;
      continue;
    }
    if (arg === '-g' || arg === '--grid') {
      options.countOrGrid = args[++i];
      continue;
    }
    if (arg === '-s' || arg === '--style') {
      options.style = args[++i];
      continue;
    }
    if (arg === '-a' || arg === '--aspect') {
      options.aspect = args[++i] as AspectRatio;
      continue;
    }
    if (arg === '-l' || arg === '--layout' || arg === '--composition') {
      options.composition = args[++i] as CompositionLayout;
      continue;
    }
    if (arg === '-p' || arg === '--pad') {
      options.pad = parseInt(args[++i], 10);
      continue;
    }
    if (arg === '-r' || arg === '--ref') {
      const val = args[++i];
      if (val) {
        const split = val.split(',').map(s => s.trim()).filter(Boolean);
        options.refImages?.push(...split);
      }
      continue;
    }
    if (arg === '-m' || arg === '--ref-mode') {
      const mode = args[++i]?.toLowerCase();
      if (mode === 'character' || mode === 'chara' || mode === 'char') {
        options.refMode = 'character';
      } else if (mode === 'style' || mode === 'art') {
        options.refMode = 'style';
      } else {
        options.refMode = 'auto';
      }
      continue;
    }
    if (arg === '--mq' || arg === '--model-quality') {
      const q = args[++i]?.toLowerCase() as ModelQuality;
      if (q === 'high' || q === 'medium' || q === 'low') {
        options.modelQuality = q;
      }
      continue;
    }
    if (arg === '-o' || arg === '--out' || arg === '--output-dir') {
      options.outDir = args[++i];
      continue;
    }
    if (arg === '-f' || arg === '--format') {
      const raw = args[++i];
      const parsed = parseOutputFormat(raw);
      if (!parsed) {
        console.error(`\x1b[31mError: Invalid format "${raw}". Use webp, png, jpeg, or jpg.\x1b[0m`);
        process.exit(1);
      }
      options.format = parsed;
      continue;
    }
    if (arg === '-q' || arg === '--quality') {
      const raw = args[++i];
      const parsed = parseInt(raw, 10);
      if (!Number.isFinite(parsed)) {
        console.error(`\x1b[31mError: Invalid quality "${raw}". Use an integer 1–100.\x1b[0m`);
        process.exit(1);
      }
      options.quality = clampEncodingQuality(parsed);
      continue;
    }
    if (arg === '--size') {
      options.size = parseInt(args[++i], 10);
      continue;
    }
    if (arg === '--items') {
      options.itemsRaw = args[++i];
      continue;
    }

    if (!arg.startsWith('-')) {
      positional.push(arg);
    }
  }

  const gridPatterns = ['1', '4', '9', '16', '1x1', '2x2', '3x3', '4x4', 'single'];
  if (!options.countOrGrid && positional.length > 0) {
    const head = positional[0].toLowerCase();
    if (gridPatterns.includes(head) || /^\d+x\d+$/.test(head)) {
      options.countOrGrid = positional[0];
      options.prompt = positional.slice(1).join(' ');
    } else {
      options.prompt = positional.join(' ');
    }
  } else {
    options.prompt = positional.join(' ');
  }

  return options;
}

async function main() {
  const args = process.argv.slice(2);
  const options = parseArgs(args);

  if (!options.prompt && !options.itemsRaw && !options.printPrompt && !options.inspectDir) {
    console.error('\x1b[31mError: Prompt is required (theme/context string).\x1b[0m');
    printHelp();
    process.exit(1);
  }

  if (options.inspectDir) {
    try {
      const result = await inspectBatch(options.inspectDir, {
        allowWeakSeams: options.allowWeakSeams,
        allowEmptyCells: options.allowEmptyCells,
        json: options.jsonOutput,
      });
      if (options.jsonOutput) {
        console.log(JSON.stringify(result, null, 2));
      } else {
        console.log(formatInspectReport(result));
      }
      process.exit(result.ok ? 0 : 1);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`\x1b[31m[INSPECT ERROR] ${message}\x1b[0m`);
      process.exit(1);
    }
  }

  try {
    await runAssetGenerator(options);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (err instanceof ItemsParseError) {
      console.error(`\x1b[31m[ITEMS ERROR] ${message}\x1b[0m`);
    } else if (err instanceof PipelineValidationError) {
      console.error(`\x1b[31m[QUALITY GATE] ${message}\x1b[0m`);
    } else {
      console.error(`\x1b[31mError: ${message}\x1b[0m`);
    }
    process.exit(1);
  }
}

if (process.argv[1]?.endsWith('cli.ts') || process.argv[1]?.endsWith('cli.js')) {
  main();
}
