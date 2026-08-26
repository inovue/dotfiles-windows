# Reference: Constrained Query Expansion (vocab-gated search)

> Adapted from upstream `Graphify-Labs/graphify` v8 (`graphify/skills/claude/references/query.md`,
> blob 56565eb, tree 43d54ac). Condensed for this Windows/PS5.1 + MCP harness.
> Load ONLY when a graph query returned 0 hits, or the graph exceeds ~2000 nodes,
> or the question uses cross-language / domain vocabulary that may not match labels.

## Why

`graphify query` (CLI and MCP) matches nodes via case-folded substring + IDF —
no stemming, no synonyms, no cross-language match. If the question's vocabulary
differs from graph labels ("認証" vs `Guardian`, "handler" vs `обработчик`),
the matcher returns 0 hits and the answer collapses to noise. Fix it by
expanding the query against the graph's REAL vocabulary — never by inventing tokens.

## Step 0 — build / refresh the vocab (deterministic, no LLM)

```powershell
python -c "import json, re; from pathlib import Path; data = json.loads(Path('graphify-out/graph.json').read_text(encoding='utf-8')); vocab = set(); [vocab.add(p.lower()) for n in data['nodes'] for c in re.findall(r'[^\W\d_]+', n.get('label','') or '', re.UNICODE) for p in (re.findall(r'[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+', c) or [c]) if 3 <= len(p) <= 30]; Path('graphify-out/.vocab.txt').write_text('\n'.join(sorted(vocab)), encoding='utf-8'); print(f'vocab: {len(vocab)} tokens')"
```

## Step 1 — select tokens (hard constraints)

1. Read `graphify-out/.vocab.txt`; pick **up to 12 tokens present in that exact list**
   that match the query intent. Never invent or substitute near-synonyms from memory.
2. Cross-language: map "認証" → `auth`/`credential`/`token` IFF present in vocab.
   Morphology: "handlers" → `handler` IFF present.
3. Zero matching tokens → report "the corpus has no relevant vocabulary for this
   question" and STOP. Do not fabricate a search or fall back to blind grep.
4. Print the selection before querying so the expansion is auditable:
   `Query expanded to (from graph vocab, N tokens): [token1, token2, ...]`

## Step 2 — re-query with the expanded string

- MCP: `query_graph(question="<expanded tokens joined by spaces>", token_budget=1200)`
- CLI: `just graph "<expanded tokens>"` (records graph contact with the guard)
- Chain tracing → DFS: `graphify query "<expanded>" --dfs --budget 1200`

## Step 3 — close the loop

After answering, save the result so the expansion history becomes a graph node
on the next update (see `references/memory.md`):

```powershell
graphify save-result --question "<original question>" --answer "<answer incl. expanded-token trace>" --type query --nodes <cited-node-labels> --outcome useful
```
