#!/usr/bin/env python3
"""Merge configs/cursor/agent-shell.json into Cursor User settings.json.

Install puts PowerShell 7 on PATH. Cursor's agent Shell tool follows
terminal.integrated.automationProfile / defaultProfile — without this merge
it stays Windows PowerShell 5.1 and bash `&&` explodes. Surgical: only the
keys in the fragment are written; every other user setting is left intact.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def _load(path: Path) -> dict:
    if not path.is_file():
        return {}
    raw = path.read_text(encoding="utf-8-sig")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise SystemExit(f"not a JSON object: {path}")
    return data


def _merged(dst: dict, frag: dict) -> dict:
    out = dict(dst)
    for key, val in frag.items():
        if key == "terminal.integrated.profiles.windows" and isinstance(val, dict):
            cur = out.get(key)
            if not isinstance(cur, dict):
                cur = {}
            cur = dict(cur)
            cur.update(val)
            out[key] = cur
        else:
            out[key] = val
    return out


def _in_sync(dst: dict, frag: dict) -> bool:
    for key, val in frag.items():
        if key == "terminal.integrated.profiles.windows" and isinstance(val, dict):
            got = dst.get(key)
            if not isinstance(got, dict):
                return False
            for pk, pv in val.items():
                if got.get(pk) != pv:
                    return False
        elif dst.get(key) != val:
            return False
    return True


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    frag_path = repo / "configs" / "cursor" / "agent-shell.json"
    dest_path = Path(os.environ.get("APPDATA", "")) / "Cursor" / "User" / "settings.json"
    check = "--check" in sys.argv[1:]
    frag = _load(frag_path)
    cursor_root = dest_path.parent.parent
    if not cursor_root.is_dir():
        print("skip: Cursor not installed", cursor_root)
        return 0
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dst = _load(dest_path) if dest_path.is_file() else {}
    if check:
        ok = _in_sync(dst, frag)
        print("in sync" if ok else "drift", dest_path)
        return 0 if ok else 1
    new = _merged(dst, frag)
    dest_path.write_text(json.dumps(new, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    print(f"merged agent-shell -> {dest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
