# Reference: Work-Memory Loop (save-result / reflect / LESSONS)

> Adapted from upstream `Graphify-Labs/graphify` v8 (`skills/claude/references/query.md`
> memory sections + `always_on/claude-md.md`, tree 43d54ac). Condensed for this harness.
> This is how semantic nodes accumulate automatically: saved Q&A results are folded
> into the graph as nodes on the next `--update`/`just update-graph` run (official spec).

## The loop

1. **Session start** — `just lessons`
   Runs `graphify reflect --if-stale` (aggregates `graphify-out/memory/` outcomes
   into `graphify-out/reflections/LESSONS.md`, deterministic, no LLM) and prints
   the lessons doc. Skim it before the first graph query: it lists which past
   answers were useful, which were dead ends, and which needed correction.

2. **After answering an architecture / impact / navigation question** — `just remember`

   ```powershell
   just remember "which files react to hooks.json changes?" "sync_agent_rules.ps1 merges it into 3 harness configs; agent_guard.py reads deployed copy"
   # full control (cited nodes, outcome):
   graphify save-result --question "..." --answer "..." --type query --nodes hooks.json agent_guard.py --outcome useful
   ```

3. **When your own earlier answer turns out wrong** — save the correction:

   ```powershell
   graphify save-result --question "..." --answer "<original>" --outcome corrected --correction "<what was actually true>"
   ```

   `dead_end` marks paths that wasted time; reflect turns repeated dead ends into
   an explicit "do not retry" lesson.

4. **Next graph update** (`just update-graph`, post-commit hook, or watch) folds
   `memory/*.json` into graph nodes — future `query_graph` calls can then land on
   past answers directly.

## Outcome vocabulary

| outcome | meaning | reflect consequence |
| :--- | :--- | :--- |
| `useful` | answer held up | reinforces the cited nodes/paths |
| `dead_end` | path went nowhere | lesson: skip this route |
| `corrected` | answer was wrong, correction attached | lesson: the correction supersedes |

## Guard integration

`agent_guard.py` v4.3 nudges once at batch end (`just remember`) when graph
queries ran in an edited session but nothing was saved. Advisory only — it never
blocks on its own. The nudge disappears once `just remember`/`graphify save-result`
is recorded in the session.
