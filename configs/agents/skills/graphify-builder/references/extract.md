# Builder runbook

Deterministic plumbing is `scripts/graphify_semantic.py` via just. The agent
only supplies judgment as JSON.

## Sequence

```powershell
just semantic-prepare
# reads: graphify-out/.graphify_uncached.txt  (relative paths, one per line)
#        graphify-out/.graphify_cached.json   (already-good nodes/edges)
#        graphify-out/.graphify_target_labels.txt  (preferred edge targets)

# If uncached is empty: stop. Cache is warm.

# Else: for each uncached file, follow extraction-spec.md and accumulate
# nodes/edges/hyperedges. Write the combined object to:
#   graphify-out/.graphify_semantic.json
# If Write is blocked: python scripts/graphify_semantic.py write-json --data '<json>' (or pipe via stdin)

just semantic-merge
```

`just semantic-merge` unions cache + `.graphify_semantic.json` +
`.graphify_chunk_*.json` (first id wins), clusters, writes `graph.json`
(shrink-guard), saves the SHA cache keyed by this spec, deletes consumed
chunk files, and clears `graphify-out/needs_update`.

`just update-graph` runs `graphify update . --force` then `rehydrate --force` so
cached INFERRED edges survive code-only rebuilds. `--force` on the AST pass is
required: an AST-only rebuild has fewer nodes than AST+INFERRED, and the
engine's shrink-guard would otherwise refuse to write. The engine may warn
about AST nodes missing `source_file` — ignore that.

## Adaptive dispatch

Let `n` = number of lines in `.graphify_uncached.txt`.

- `n == 0` — do nothing
- `n <= 8` — this agent reads the files and writes one `.graphify_semantic.json`
- `n > 8` — split into chunks of ~12 files; launch `generalPurpose` subagents
  in **one** message; each subagent loads `extraction-spec.md` and writes
  `graphify-out/.graphify_chunk_NN.json`; then `just semantic-merge`
  (unions chunks + `.graphify_semantic.json`, first id wins).

Do not use Explore subagents (read-only; they cannot write chunks).

## Quality bar

- Every INFERRED edge has `source_location` (`L12`) and a rubric score.
- Prefer edges onto labels in `graphify-out/.graphify_target_labels.txt`
  (written by prepare from existing `graph.json`) over new duplicate heading
  nodes. Fall back to function names and script basenames.
- Pointer-only `@AGENTS.md` files and `graphify-out/` are filtered by prepare
  (do not extract them).
- Cap ~12 concept/rationale nodes per source file.
- `graphify update` may warn that AST nodes lack `source_file` — ignore; that
  is the engine, not the agent JSON.
