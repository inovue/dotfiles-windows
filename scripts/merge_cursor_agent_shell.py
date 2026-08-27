#!/usr/bin/env python3
"""Merge configs/cursor/harness-settings.json into Cursor User settings.json.

Install puts PowerShell 7 on PATH. Cursor's agent Shell tool follows
terminal.integrated.automationProfile / defaultProfile — without this merge
it stays Windows PowerShell 5.1 and bash `&&` explodes. Surgical: only the
keys in the fragment are written; every other user setting is left intact.

Legacy: configs/cursor/agent-shell.json is merged if harness-settings.json is absent.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

PROFILE_KEY = "terminal.integrated.profiles.windows"
AUTOMATION_KEY = "terminal.integrated.automationProfile.windows"


def _load(path: Path) -> dict:
    if not path.is_file():
        return {}
    raw = path.read_text(encoding="utf-8-sig")
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise SystemExit(f"not a JSON object: {path}")
    return data


def _merge_automation(dst: dict | None, frag: dict) -> dict:
    out = dict(dst or {})
    for key, val in frag.items():
        if key == "env" and isinstance(val, dict):
            env = dict(out.get("env") or {})
            env.update(val)
            out["env"] = env
        else:
            out[key] = val
    return out


def _merged(dst: dict, frag: dict) -> dict:
    out = dict(dst)
    for key, val in frag.items():
        if key == PROFILE_KEY and isinstance(val, dict):
            cur = out.get(key)
            if not isinstance(cur, dict):
                cur = {}
            cur = dict(cur)
            cur.update(val)
            out[key] = cur
        elif key == AUTOMATION_KEY and isinstance(val, dict):
            out[key] = _merge_automation(out.get(key), val)
        else:
            out[key] = val
    return out


def _automation_in_sync(got: dict | None, want: dict) -> bool:
    if not isinstance(got, dict):
        return False
    for key, val in want.items():
        if key == "env" and isinstance(val, dict):
            genv = got.get("env") or {}
            if not isinstance(genv, dict):
                return False
            for ek, ev in val.items():
                if genv.get(ek) != ev:
                    return False
        elif got.get(key) != val:
            return False
    return True


def _in_sync(dst: dict, frag: dict) -> bool:
    for key, val in frag.items():
        if key == PROFILE_KEY and isinstance(val, dict):
            got = dst.get(key)
            if not isinstance(got, dict):
                return False
            for pk, pv in val.items():
                if got.get(pk) != pv:
                    return False
        elif key == AUTOMATION_KEY and isinstance(val, dict):
            if not _automation_in_sync(dst.get(key), val):
                return False
        elif dst.get(key) != val:
            return False
    return True


def _fragment_path(repo: Path) -> Path:
    primary = repo / "configs" / "cursor" / "harness-settings.json"
    if primary.is_file():
        return primary
    return repo / "configs" / "cursor" / "agent-shell.json"


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    frag_path = _fragment_path(repo)
    dest_path = Path(os.environ.get("APPDATA", "")) / "Cursor" / "User" / "settings.json"
    check = "--check" in sys.argv[1:]
    if not frag_path.is_file():
        raise SystemExit(f"fragment not found: {frag_path}")
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
    print(f"merged harness-settings -> {dest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
