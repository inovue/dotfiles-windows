# Semantic extraction spec

Output ONLY valid JSON matching the schema below — no markdown fences, no preamble.
This file is the cache prompt fingerprint; changing it invalidates semantic cache hits.

## Scope

- Docs / papers / images only. Do not re-extract code (AST already owns symbols).
- Do not recreate file/section nodes the AST already has (same heading text).
- When a doc names a command, script, or function, emit an edge to that **existing label**.

`file_type` MUST be one of: `document`, `paper`, `image`, `rationale`, `concept`.

Node ID: lowercase `[a-z0-9_]` only. Format `{parent}_{stem}_{entity}` where parent is
the immediate directory (omit for top-level files), stem is the filename without
extension, entity is the concept. `configs/agents/GLOBAL_RULES.md` + `Token economy`
→ `agents_global_rules_token_economy`. IDs must be deterministic from the label.
Never append chunk suffixes.

## Confidence rubric (INFERRED only)

- **0.95** — explicit cross-file reference, one plausible target
- **0.85** — naming + context align
- **0.75** — reasonable but not explicit
- **0.65** — naming similarity only
- **0.55** — speculative (prefer omit)

EXTRACTED is for quotes/copy that appear verbatim in the doc (rare here).
Default new docs↔code edges as INFERRED.

Relations: `documents`, `implements`, `references`, `cites`,
`conceptually_related_to`, `shares_data_with`, `semantically_similar_to`,
`rationale_for`.

## Schema

```json
{
  "nodes": [
    {
      "id": "agents_global_rules_ssot",
      "label": "SSOT flow",
      "file_type": "concept",
      "source_file": "configs/agents/GLOBAL_RULES.md",
      "source_location": "L12",
      "source_url": null,
      "captured_at": null,
      "author": null,
      "contributor": null
    }
  ],
  "edges": [
    {
      "source": "agents_global_rules_ssot",
      "target": "sync_agent_rules",
      "relation": "documents",
      "confidence": "INFERRED",
      "confidence_score": 0.85,
      "source_file": "configs/agents/GLOBAL_RULES.md",
      "source_location": "L12",
      "weight": 1.0
    }
  ],
  "hyperedges": [],
  "input_tokens": 0,
  "output_tokens": 0
}
```

`source_file` is repo-relative with forward slashes. `source_location` is `L<line>`.
Set `input_tokens` / `output_tokens` to 0; the host may overwrite them.
