# Reference: Freshness — update / check-update / watch / builder

> Engine commands come from Graphify-Labs/graphify. Semantic judgment is
> session-bound (skill `graphify-builder`), not `graphify extract`.

## Which command when

| Situation | Command | LLM? |
| :--- | :--- | :--- |
| Edited code this batch | `just update-graph` (`graphify update . --force` + rehydrate) | No |
| Committed / checked out / merged | git hooks rebuild AST only and may no-op (shrink-guard) while INFERRED nodes exist. Recover with `just update-graph` (`--force` + rehydrate). | No (AST). Cached semantic is rehydrated on `just update-graph` / `just lessons` |
| Docs, images changed; prepare lists uncached files | skill `graphify-builder` → `just semantic-merge` | Yes — **this session's model only** |
| Want to know if semantic re-extraction is pending | `just check-semantic` (needs_update **and** SHA-uncached list) / `just semantic-prepare` | No |
| Long session, want AST freshness | `just watch` (`graphify watch .`) | No |

## Incremental logic (upstream `detect_incremental`)

- **Code-only diffs** → fast path: AST re-extraction of changed files. `just update-graph` passes `--force` (INFERRED nodes make AST-only rebuilds look like shrink) then rehydrates cached semantic so INFERRED edges are not wiped.
- **Docs / images** → AST alone cannot capture semantics; the engine sets a `needs_update` flag. Clear it with builder + `just semantic-merge`, not `graphify extract`.
- `--force` / `GRAPHIFY_FORCE=1` bypasses the manifest gate and semantic cache.

## Watch mode

`just watch` is `graphify watch . --debounce 3`: AST rebuilds on code changes.
Doc changes only set `needs_update`. There is no auto-LLM and no
`GRAPHIFY_SEMANTIC_AUTO`.

## Git hooks

`graphify hook install` (rerun after upgrades) installs post-commit,
post-checkout and a merge driver — AST-only, no `--force`, no rehydrate.
After a commit that follows a semantic merge, the hook may refuse to write
(shrink-guard). Do not patch the vendor hook; run `just update-graph` to
recover. `just install-graph-hook` remains the one-per-clone entry point.

## LLM for semantic

The host coding agent. Never a second API key path for this harness.
`just setup-keys` is unrelated (other tools).
