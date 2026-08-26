---
trigger: always_on
description: Bottom-Up line-numbered edits to avoid line-shift re-reads. Antigravity-only (replace_file_content).
---

# Line-Numbered Edit Orchestration (Antigravity)

`replace_file_content` requires StartLine/EndLine. Editing top-down shifts every later line number and forces a verification re-read.

## Bottom-Up Rule

When applying multiple replacements in one file with a line-numbered tool:

1. Sort targets by StartLine descending (file bottom → top).
2. Apply each replacement without re-reading.
3. Treat the tool's success snippet as verification.

Do not compute in-memory line deltas after a top-down edit — a miscount silently corrupts the wrong lines. Bottom-Up keeps every remaining StartLine/EndLine valid.

## When not to use this

If a content-addressed editor (`StrReplace`, `str_replace`, `apply_patch`) or a counted `sd`/`ast-grep` batch is available, prefer those. This rule exists only because Antigravity's editor is line-numbered.

## Atomic multi-chunk alternative

Same-file 3+ replacements: counted `sd` or `ast-grep -U` in one command (skill `modern-cli-expert`). Regex replace without a match-count assert is forbidden (silent over-replace).
