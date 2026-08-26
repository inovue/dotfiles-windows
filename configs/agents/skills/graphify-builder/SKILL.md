---
name: graphify-builder
description: >-
  Session-bound semantic graph builder. Use when just check-semantic or just
  semantic-prepare reports uncached docs/images, when the user asks to refresh
  the meaning layer of the knowledge graph, or after editing markdown/images.
  Host-agent tokens only — never graphify extract, never a second API.
---

# Graphify Builder

Add **INFERRED** docs↔code edges using the current session model. AST code
extraction stays on the CLI (`just update-graph` / git hooks). Do not install
the upstream `/graphify` skill. Do not call `graphify extract`.

Load `references/extract.md` for the exact CLI sequence and `references/extraction-spec.md`
only when writing JSON.

## When to use

- `just semantic-prepare` printed uncached files
- `just check-semantic` reports `needs_update` **or** SHA-uncached docs (`graphify-out/.graphify_uncached.txt`). `graphify check-update` can be clean while prepare still lists files — trust prepare.
- User asked to refresh the semantic graph
- This batch edited `.md` / images and you are about to finish

## When NOT to use

- Code-only edits → `just update-graph` (rehydrate replays cache, no LLM)
- Answering architecture questions against an existing graph → skill `graphify-navigator`
- Cache is warm (prepare says 0 uncached) → skip

## Hard rules

1. Never edit `graphify-out/graph.json` by hand. Write `.graphify_semantic.json`, then `just semantic-merge`.
2. Never start a second LLM (`graphify extract`, Gemini/OpenRouter "for graphify").
3. Do not recreate AST heading/symbol nodes. Link to existing labels.
4. Uncached count ≤ 8: extract inline in this agent. Count > 8: dispatch `generalPurpose` subagents in one message (chunk ~12 files); each writes `.graphify_chunk_NN.json`; then `just semantic-merge` (unions chunks).
