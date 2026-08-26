# Reference: Freshness — update / check-update / watch / extract

> Adapted from upstream `Graphify-Labs/graphify` v8 (`skills/claude/references/update.md`
> blob 3632fd4, `hooks.md` blob 438b8b1, `add-watch.md`, tree 43d54ac). Condensed.

## Which command when

| Situation | Command | LLM? |
| :--- | :--- | :--- |
| Edited code this batch | `just update-graph` (`graphify update .`) | No — AST re-extract, seconds |
| Committed / checked out / merged | nothing — git hooks (`graphify hook install`) fire automatically | No |
| Docs, images, or memory/ changed | `just update-semantic` (`graphify extract .`) | Yes — headless semantic extraction |
| Want to know if semantic re-extraction is pending | `just check-semantic` (`graphify check-update .`) | No — reads needs_update flag |
| Long session, want zero-thought freshness | `just watch` (see below) | AST auto; semantic per env var |

## Incremental logic (upstream `detect_incremental`)

- **Code-only diffs** → fast path: AST re-extraction of changed files, graph
  rewritten in place. This never requires an LLM and is safe to run per batch.
- **Docs / images / new URL content** → AST alone cannot capture semantics; the
  engine sets a `needs_update` flag instead of silently degrading the graph.
  `check-update` reports it (cron-safe exit codes); `extract` clears it.
- `--force` / `GRAPHIFY_FORCE=1` bypasses the manifest gate and semantic cache.

## Watch mode (this harness: `just watch` → `scripts/graph_watch.ps1`)

- Runs `graphify watch . --debounce 3`: rebuilds AST graph on every code change.
- Semantic escalation is two-tier via `GRAPHIFY_SEMANTIC_AUTO`:
  - unset (default): needs_update is only reported (audit + batch end notice).
  - `1`: the watcher auto-runs `just update-semantic` when the flag appears
    (uncapped LLM cost mode — deliberate opt-in).

## Git hooks

`graphify hook install` (rerun after upgrades) installs post-commit, post-checkout
and a merge driver — all AST-only, so they are fast and never call an LLM. The
`just install-graph-hook` recipe remains the one-per-clone entry point.

## LLM backend for `extract`

Uses keys from `just setup-keys` (OpenAI-compatible: set `OPENAI_BASE_URL` for
LM Studio / vLLM; Anthropic-compatible endpoints also supported). Tune with
`--token-budget`, `--max-concurrency` (set 1 for local LLMs), `--api-timeout`.
