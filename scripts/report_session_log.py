#!/usr/bin/env python3
"""Summarize graphify-out/session-log.jsonl: deny / thrash / crawl / poll-guide rates."""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "graphify-out" / "session-log.jsonl"


def main() -> int:
    if not LOG.is_file():
        print(f"[SKIP] no session log at {LOG}")
        return 0
    rows = []
    with LOG.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    real_rows = [r for r in rows if not r.get("test")]
    test_rows = [r for r in rows if r.get("test")]
    total = len(real_rows) if real_rows else len(rows)
    denied = sum(1 for r in (real_rows or rows) if r.get("denied") or r.get("decision") == "deny")
    thrash = sum(1 for r in (real_rows or rows) if r.get("thrash"))
    crawl = sum(1 for r in (real_rows or rows) if r.get("crawl"))
    poll_guide = sum(1 for r in (real_rows or rows) if r.get("poll_guide"))
    reads = sum(1 for r in (real_rows or rows) if str(r.get("tool") or "") in {
        "view_file", "readfile", "read_file", "view", "read", "cat", "get_content",
    })
    deny_rate = (denied / total * 100) if total else 0.0
    thrash_rate = (thrash / reads * 100) if reads else 0.0
    max_lines = 0
    for r in (real_rows or rows):
        try:
            max_lines = max(max_lines, int(r.get("read_lines_max") or 0))
        except (TypeError, ValueError):
            continue
    harnesses = Counter(str(r.get("harness") or "unknown") for r in (real_rows or rows))
    harness_txt = ", ".join(f"{k}={v}" for k, v in sorted(harnesses.items()))
    print(f"session-log: {LOG}")
    print(f"  events        : {total}" + (f"  (excluded {len(test_rows)} test)" if test_rows else ""))
    print(f"  denied        : {denied} ({deny_rate:.1f}%)")
    print(f"  reads         : {reads}")
    print(f"  thrash (read-after-edit): {thrash} ({thrash_rate:.1f}% of reads)")
    print(f"  crawl (cumulative-line cap): {crawl}")
    print(f"  poll_guide (short-wait streak): {poll_guide}")
    print(f"  read_lines_max: {max_lines}")
    print(f"  harnesses     : {harness_txt}")
    if thrash == 0 and (crawl or poll_guide):
        print("  note          : thrash 0% is not token-efficiency; check crawl / poll_guide")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
