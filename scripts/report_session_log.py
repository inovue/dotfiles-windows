#!/usr/bin/env python3
"""Summarize graphify-out/session-log.jsonl: deny rate and read-after-edit (thrash) rate."""
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
    total = len(rows)
    denied = sum(1 for r in rows if r.get("denied") or r.get("decision") == "deny")
    thrash = sum(1 for r in rows if r.get("thrash"))
    reads = sum(1 for r in rows if str(r.get("tool") or "") in {
        "view_file", "readfile", "read_file", "view", "read", "cat", "get_content",
    })
    deny_rate = (denied / total * 100) if total else 0.0
    thrash_rate = (thrash / reads * 100) if reads else 0.0
    harnesses = Counter(str(r.get("harness") or "unknown") for r in rows)
    harness_txt = ", ".join(f"{k}={v}" for k, v in sorted(harnesses.items()))
    print(f"session-log: {LOG}")
    print(f"  events        : {total}")
    print(f"  denied        : {denied} ({deny_rate:.1f}%)")
    print(f"  reads         : {reads}")
    print(f"  thrash (read-after-edit): {thrash} ({thrash_rate:.1f}% of reads)")
    print(f"  harnesses     : {harness_txt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
