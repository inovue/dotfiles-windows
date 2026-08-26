#!/usr/bin/env python3
"""
Agent Guard v2: Stability-First Deterministic Governor (PreToolUse lifecycle hook).

Validates tool invocations, enforces safety invariants, and limits token waste,
while guaranteeing the agent loop can NEVER deadlock or spin on guard denials.

Stability invariants (v2 hardening after Antigravity CLI field report):
 1. FAIL-OPEN     : any internal error yields {"decision": "allow"}; exit code is always 0.
 2. ONE-STRIKE    : except for destructive commands, the same target is never denied
                    twice in a session. A guidance deny costs at most 1 tool call
                    and can never loop. Destructive commands stay hard-denied forever.
 3. DENY-IF-CHEAPER: a deny must save more than the tool call it wastes. Whole-file
                    reads up to 300 lines are ALLOWED (one full read is cheaper than
                    the 3x sliced re-reads the old 120-line cap provoked).
 4. STATE TTL     : session state expires after 2h and old state files are garbage
                    collected, so a stale/shared state file can never starve a new
                    session's read budget (the v1 "default"-session starvation bug).
 5. EXACT RECOVERY: every deny message contains a concrete, copy-pastable next step
                    (exact slice bounds, exact rtk-prefixed command, exact CLI swap).
"""
import sys
import json
import re
import os
import time
import tempfile
from itertools import islice
from pathlib import Path
from shutil import which

# --- Tunables -----------------------------------------------------------------
MAX_UNSLICED_LINE_COUNT = 300   # <=300 lines: 1 full read is cheaper than N slices
MAX_READ_BUDGET = 8             # unique files per session window (resets on edit/TTL)
SLICE_HINT_SIZE = 300           # suggested slice height in deny guidance
STATE_TTL_SECONDS = 2 * 60 * 60
STATE_GC_SECONDS = 24 * 60 * 60

# 1. Critical destructive patterns (Hard Deny, no one-strike escape)
DANGEROUS_PATTERNS = [
    (r"\bformat\s+[a-zA-Z]:", "Disk formatting command detected"),
    (r"\bdiskpart\b", "Disk partitioning command detected"),
    (r"\brmdir\s+/[sS]\s+/[qQ]\s+[cC]:\\(?:\s|$)", "Root drive recursive wipe detected"),
    (r"\brm\s+-rf\s+/[*\s]*$", "Root filesystem wipe detected"),
    (r"git\s+push\s+[^;|\n]*--force[^\n]*\b(?:main|master)\b", "Force push to protected branch blocked"),
    (r"(?:curl|iwr|Invoke-WebRequest)[^\n|]*\|\s*(?:iex|Invoke-Expression)", "Unverified remote script execution pipe blocked"),
]

# 2. Slow PowerShell cmdlets violating Modern CLI Invariants (one-strike deny)
SLOW_CLI_PATTERNS = [
    (r"\bGet-ChildItem\b[^\n|]*-Recurse\b", "Use 'fd <pattern>' instead of 'Get-ChildItem -Recurse'"),
    (r"\bSelect-String\b", "Use 'rg -n <pattern>' instead of 'Select-String'"),
]

# 3. Noisy commands that must be wrapped by the rtk token proxy (one-strike deny)
RTK_NOISY_PATTERN = re.compile(
    r"(?:^|[;&|]\s*)(git\s+(?:status|log|diff|show)\b[^;&|\n]*)", re.IGNORECASE
)


def allow(reason: str = "") -> dict:
    res = {"decision": "allow"}
    if reason:
        res["reason"] = reason
    return res


def deny(reason: str) -> dict:
    return {"decision": "deny", "reason": reason}


# --- Session state (TTL + garbage collection) ----------------------------------
def _state_dir() -> Path:
    d = Path(tempfile.gettempdir()) / "agy_agent_guard"
    d.mkdir(parents=True, exist_ok=True)
    return d


def get_state_file(conv_id: str) -> Path:
    safe_id = re.sub(r"[^a-zA-Z0-9_-]", "_", conv_id or "default")
    return _state_dir() / f"session_{safe_id}.json"


def gc_stale_state_files() -> None:
    """Best-effort removal of state files older than STATE_GC_SECONDS."""
    try:
        now = time.time()
        for f in _state_dir().glob("session_*.json"):
            if now - f.stat().st_mtime > STATE_GC_SECONDS:
                f.unlink(missing_ok=True)
    except Exception:
        pass


def fresh_state() -> dict:
    return {"ts": time.time(), "reads": [], "strikes": {}}


def load_state(conv_id: str) -> dict:
    state_file = get_state_file(conv_id)
    if state_file.exists():
        try:
            with open(state_file, "r", encoding="utf-8") as f:
                state = json.load(f)
            # TTL guard: a stale session (or shared fallback file) must never
            # carry an exhausted read budget into a new session.
            if time.time() - float(state.get("ts", 0)) > STATE_TTL_SECONDS:
                return fresh_state()
            return state
        except Exception:
            pass
    return fresh_state()


def save_state(conv_id: str, state: dict) -> None:
    try:
        state["ts"] = state.get("ts") or time.time()
        with open(get_state_file(conv_id), "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
    except Exception:
        pass


def first_strike(state: dict, key: str) -> bool:
    """Record a guidance strike. Returns True only the FIRST time a key is seen,
    guaranteeing the same target is never denied twice (anti-deadlock)."""
    strikes = state.setdefault("strikes", {})
    if key in strikes:
        return False
    strikes[key] = time.time()
    return True


# --- Inspectors -----------------------------------------------------------------
def inspect_run_command(args: dict, conv_id: str) -> dict:
    cmd = args.get("CommandLine") or args.get("command") or args.get("cmd") or args.get("script") or ""

    # Gate 1: destructive commands — unconditional hard deny (no one-strike).
    for pattern, reason in DANGEROUS_PATTERNS:
        if re.search(pattern, cmd, re.IGNORECASE):
            return deny(f"Agent Guard [Safety Block]: {reason} -> '{cmd[:70]}...'")

    state = load_state(conv_id)

    # Gate 2: slow PowerShell cmdlets — one-strike guidance deny.
    for pattern, guidance in SLOW_CLI_PATTERNS:
        if re.search(pattern, cmd, re.IGNORECASE):
            if first_strike(state, f"slow:{cmd[:80]}"):
                save_state(conv_id, state)
                return deny(f"Agent Guard [Modern CLI Invariant]: {guidance} (retry passes; one-strike)")
            save_state(conv_id, state)
            return allow()

    # Gate 3: rtk token-proxy enforcement — one-strike, only when rtk is installed.
    if which("rtk") and not re.search(r"(?:^|[;&|(\s])rtk\s", cmd):
        m = RTK_NOISY_PATTERN.search(cmd)
        if m:
            noisy = m.group(1).strip()
            if first_strike(state, f"rtk:{noisy[:80]}"):
                save_state(conv_id, state)
                return deny(
                    f"Agent Guard [Token Economy]: prefix noisy output with rtk -> "
                    f"run 'rtk {noisy}' instead (retry passes; one-strike)"
                )
            save_state(conv_id, state)
            return allow()

    return allow()


def count_lines_capped(path_obj: Path, cap: int) -> int:
    """Count lines up to cap+1 (O(cap) worst case, safe on huge files)."""
    with open(path_obj, "r", encoding="utf-8", errors="ignore") as f:
        return sum(1 for _ in islice(f, cap + 1))


def inspect_view_file(args: dict, conv_id: str) -> dict:
    target_path = args.get("AbsolutePath") or args.get("TargetFile") or args.get("path") or args.get("file_path") or args.get("filename") or ""
    start_line = args.get("StartLine") or args.get("start_line") or args.get("offset")
    end_line = args.get("EndLine") or args.get("end_line") or args.get("limit")

    if not target_path:
        return allow()

    path_obj = Path(target_path)
    file_name = path_obj.name.lower()

    # Skill documentation and rule entrypoints are exempt from caps and budget.
    is_exempt = file_name in ["skill.md", "agents.md", "claude.md", ".cursorrules", "gemini.md", "hooks.json"] or "skills" in target_path.lower()

    state = load_state(conv_id)

    # Gate 1: un-sliced whole-file read of a genuinely large file (one-strike).
    if not is_exempt and start_line is None and end_line is None and path_obj.is_file():
        try:
            line_count = count_lines_capped(path_obj, MAX_UNSLICED_LINE_COUNT)
            if line_count > MAX_UNSLICED_LINE_COUNT:
                if first_strike(state, f"read:{target_path}"):
                    save_state(conv_id, state)
                    return deny(
                        f"Agent Guard [Read Budget Invariant]: '{path_obj.name}' exceeds {MAX_UNSLICED_LINE_COUNT} lines. "
                        f"Locate first: rg -n \"<pattern>\" \"{path_obj.name}\" — then read ONE slice "
                        f"(StartLine=<hit-{SLICE_HINT_SIZE // 10}>, EndLine=<hit+{SLICE_HINT_SIZE // 10}>). "
                        f"If the full file is truly required, retry as-is (one-strike; retry passes)."
                    )
                save_state(conv_id, state)
                return allow()
        except Exception:
            pass

    # Gate 2: unique-file read budget (one-strike per file over budget).
    read_list = state.get("reads", [])
    if target_path not in read_list and not is_exempt:
        if len(read_list) >= MAX_READ_BUDGET:
            if first_strike(state, f"budget:{target_path}"):
                save_state(conv_id, state)
                return deny(
                    f"Agent Guard [Read Budget Invariant]: {len(read_list)} unique files already read this session. "
                    f"Prefer targeted 'rg -n' / 'ast-grep' snippets or synthesize findings now. "
                    f"If this read is essential, retry as-is (one-strike; retry passes)."
                )
        read_list.append(target_path)
        state["reads"] = read_list

    save_state(conv_id, state)
    return allow()


def inspect_write_to_file(args: dict) -> dict:
    target_file = args.get("TargetFile") or args.get("path") or args.get("file_path") or ""
    metadata = args.get("ArtifactMetadata")

    if metadata and target_file and "brain" not in target_file.lower():
        return deny(
            "Agent Guard [Workspace Edit Invariant]: Do NOT use write_to_file with ArtifactMetadata "
            "on workspace project files. Use replace_file_content for atomic surgical edits."
        )
    return allow()


# --- Entry point ------------------------------------------------------------------
def main() -> None:
    try:
        raw_input_data = sys.stdin.read()
        if not raw_input_data or not raw_input_data.lstrip('\ufeff').strip():
            print(json.dumps(allow()))
            return
        payload = json.loads(raw_input_data.lstrip('\ufeff').strip())

        tool_call = payload.get("toolCall") or payload.get("tool_call") or payload
        tool_name = (
            tool_call.get("name") or tool_call.get("tool_name")
            or payload.get("name") or payload.get("tool_name") or ""
        ).lower()
        args = (
            tool_call.get("args") or tool_call.get("arguments") or tool_call.get("parameters")
            or payload.get("args") or payload.get("tool_input") or payload.get("input") or {}
        )
        conv_id = (
            payload.get("conversationId") or payload.get("conversation_id")
            or payload.get("session_id") or payload.get("sessionId")
            or f"pid{os.getppid()}"
        )

        gc_stale_state_files()

        if tool_name in ["run_command", "bash", "execute_command", "powershell", "terminal", "exec", "shell"]:
            print(json.dumps(inspect_run_command(args, conv_id)))
            return

        if tool_name in ["view_file", "readfile", "read_file", "view", "cat", "get_content", "read"]:
            print(json.dumps(inspect_view_file(args, conv_id)))
            return

        if tool_name in ["write_to_file", "writefile", "write_file", "write", "create_file"]:
            print(json.dumps(inspect_write_to_file(args)))
            return

        if tool_name in ["replace_file_content", "editfile", "edit_file", "edit", "str_replace_editor", "strreplace"]:
            # On file edits, reset the read budget for the next iteration cycle
            # (strikes are kept: guidance stays one-shot for the whole session).
            state = load_state(conv_id)
            state["reads"] = []
            save_state(conv_id, state)
            print(json.dumps(allow()))
            return

        print(json.dumps(allow()))
    except Exception as e:
        # Fail open: never lock the agent loop on parser/IO glitches.
        print(json.dumps(allow(f"Agent Guard warning: {str(e)}")))


if __name__ == "__main__":
    main()
