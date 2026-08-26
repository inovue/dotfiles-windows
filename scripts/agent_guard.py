#!/usr/bin/env python3
"""
Agent Guard v4.2: Graph-First Deterministic Governor (PreToolUse / stop lifecycle hook).

Validates tool invocations, enforces safety invariants, limits token waste,
and mechanically requires graph contact before unanchored search or multi-file
edits when graphify-out/graph.json exists.

Stability invariants (v2 hardening after Antigravity CLI field report):
 1. GUARDED FAIL-OPEN: any internal error yields {"decision": "allow"} and exit code 0,
                    BUT the raw payload is best-effort scanned against the destructive
                    patterns first — a parse glitch can no longer smuggle a wipe through.
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

Obfuscation resistance (v3 hardening after security review):
 - Patterns are matched against the raw command AND an escape-stripped variant
   (PowerShell backtick / cmd caret removed), defeating i`ex-style token splitting.
 - Flag order is normalized via lookaheads (rd /q /s == rd /s /q, -f == --force).
 - Encoded execution (powershell -enc/-e/-ec), Base64-decode-then-invoke, and
   download-and-execute in BOTH pipe and argument form are hard-denied.
 - NOT a sandbox: a determined injected payload can still evade any regex layer.
   OS-level containment (non-admin agent account, harness approval flow) remains
   the real boundary; this guard is a seatbelt against agent mistakes.

Graph-first walls (v4):
 - GRAPH-GATE : if graph.json exists and no graph query has been recorded this
                session, unanchored rg/fd/Grep is one-strike denied.
 - EDIT-GATE  : first edit without graph contact is one-strike denied; retry of
                the same file is the pinpoint escape. A second file without
                graph contact is one-strike denied per path.
 - BATCH-END  : stop/sessionEnd injects a one-shot follow-up if edits happened
                without `just update-graph` and `just audit`.
 - SESSION LOG: append-only JSONL at graphify-out/session-log.jsonl (ground truth
                for later performance review; never a substitute for tests).
 - CONV-ID (v4.1): payload session keys first; never getppid() (Windows hook
                wrappers get a new PID per call and broke one-strike). Fallback
                is repo-root + TTL window. Deny/allow emit user_message.
 - THRASH (v4.1): read-after-edit within 120s is allow + guidance, never deny.

Multi-harness ACI (v4.2):
 - DETECT     : cursor_version → Cursor; CLAUDE_PROJECT_DIR / permission_mode
                → Claude Code; else Antigravity (legacy decision/permission JSON).
 - CLAUDE OUT : PreToolUse emits only hookSpecificOutput.permissionDecision;
                deny also writes the reason to stderr and exits 2 so a schema
                drift cannot fail-open. Stop uses decision:block (once).
                stop_hook_active short-circuits to prevent a stop loop.
 - STATE MERGE: save_state re-reads the file and unions strikes/reads/edit_files
                (OR for flags) so parallel hook processes cannot clobber one-strike.
 - FALLBACK   : win{N}_{digest} loads win{N-1}_{digest} when the current window
                file is missing and the previous file is still inside TTL.
 - KNOWN LIMIT: concurrent Antigravity sessions that omit a session key still
                share the repo+window fallback id. One-strike + merge keeps the
                harm to at most one extra retry, not a deadlock.
"""
import sys
import json
import re
import os
import time
import hashlib
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
THRASH_WINDOW_SECONDS = 120     # read-after-edit soft guidance window

# 1. Critical destructive patterns (Hard Deny, no one-strike escape).
# Matched case-insensitively against the raw command AND an escape-stripped
# variant (see find_dangerous). Lookaheads make flag/argument order irrelevant.
_STMT = r"[^\n;&|]*"  # stay inside one shell statement
_BARE_ROOT = r"(?:\$env:USERPROFILE|\$HOME|~|[a-zA-Z]:)[\\/]?[\"']?\s*(?:$|[;&|,\s])"

DANGEROUS_PATTERNS = [
    # --- disk / volume destruction ---
    (r"\bformat\s+[a-zA-Z]:", "Disk formatting command detected"),
    (r"\b(?:format-volume|clear-disk|initialize-disk|remove-partition)\b",
     "PowerShell disk-destruction cmdlet detected"),
    (r"\bdiskpart\b", "Disk partitioning command detected"),

    # --- recursive wipe of drive roots / user profile ---
    # cmd.exe style: rmdir|rd with /s (any flag order) aimed at a bare drive root
    (r"\b(?:rmdir|rd)\b(?=" + _STMT + r"\s/[sS]\b)" + _STMT +
     r"\s[\"']?[a-zA-Z]:[\\/]?[\"']?\s*(?:$|[;&|])",
     "Drive-root recursive wipe detected"),
    # unix style: rm with any -r… flag combo aimed at /, /*, ~ or $HOME
    (r"\brm\b(?=" + _STMT + r"\s-[a-zA-Z]*r)" + _STMT +
     r"\s[\"']?(?:/\*?|~|\$HOME)[\"']?\s*(?:$|[;&|])",
     "Root/home filesystem wipe detected"),
    # PowerShell style: Remove-Item & aliases aimed at a BARE profile/drive root
    # (deleting subdirectories like $env:USERPROFILE\.cache stays allowed)
    (r"\b(?:remove-item|ri|rm|rd|del|erase)\b(?=" + _STMT + r"\s-[a-zA-Z]*r)"
     r"(?=" + _STMT + r"[\s\"'(,]" + _BARE_ROOT + r")",
     "User-profile/drive-root recursive wipe detected"),

    # --- encoded / obfuscated execution ---
    # powershell -enc/-en/-ec/-e … (parameter-prefix abbreviations included);
    # scan stops at -File so trailing SCRIPT arguments cannot false-positive.
    (r"\b(?:powershell|pwsh)(?:\.exe)?\b(?:(?!\s-[fF]ile\b)[^\n;&])*\s-(?:enc\w*|en|ec|e)\b",
     "Encoded PowerShell execution (-EncodedCommand) blocked"),
    # Base64 decode co-occurring with dynamic invocation (either order)
    (r"frombase64string[^\n;&]*(?:\biex\b|invoke-expression|invoke-command|::create)"
     r"|(?:\biex\b|invoke-expression|invoke-command|::create)[^\n;&]*frombase64string",
     "Base64-decoded dynamic execution blocked"),

    # --- download-and-execute (pipe AND argument form) ---
    (r"\b(?:curl|wget|iwr|irm|invoke-webrequest|invoke-restmethod)\b[^\n|]*\|[^\n;&]*"
     r"\b(?:iex|invoke-expression)\b",
     "Unverified remote script execution pipe blocked"),
    (r"\b(?:iex|invoke-expression)\b" + _STMT +
     r"(?:\biwr\b|\birm\b|\bcurl\b|\bwget\b|invoke-webrequest|invoke-restmethod"
     r"|downloadstring|downloadfile|net\.webclient)"
     r"|::create\([^\n;&]*(?:\biwr\b|\birm\b|invoke-webrequest|invoke-restmethod|downloadstring)",
     "Unverified remote script execution (argument form) blocked"),

    # --- git force push to protected branches (--force-with-lease stays allowed) ---
    (r"git\s+push\b(?=" + _STMT + r"\s(?:--force\b(?!-)|-f\b))"
     r"(?=" + _STMT + r"\b(?:main|master)\b(?![\w-]))",
     "Force push to protected branch blocked (--force-with-lease is allowed)"),
]


def strip_shell_escapes(text: str) -> str:
    """PS backticks and cmd carets are transparent to the shell but opaque to
    regexes (i`ex, for^mat). Strip them so the normalized variant is scannable."""
    return re.sub(r"[`^]", "", text)


def find_dangerous(text: str):
    """Return the matched deny reason, or None. Scans raw + escape-stripped."""
    if not text:
        return None
    for variant in (text, strip_shell_escapes(text)):
        for pattern, reason in DANGEROUS_PATTERNS:
            if re.search(pattern, variant, re.IGNORECASE):
                return reason
    return None

# 2. Slow PowerShell cmdlets violating Modern CLI Invariants (one-strike deny)
SLOW_CLI_PATTERNS = [
    (r"\bGet-ChildItem\b[^\n|]*-Recurse\b", "Use 'fd <pattern>' instead of 'Get-ChildItem -Recurse'"),
    (r"\bSelect-String\b", "Use 'rg -n <pattern>' instead of 'Select-String'"),
]

# 3. Noisy commands that must be wrapped by the rtk token proxy (one-strike deny)
RTK_NOISY_PATTERN = re.compile(
    r"(?:^|[;&|]\s*)(git\s+(?:status|log|diff|show)\b[^;&|\n]*)", re.IGNORECASE
)

# 4. Graph-first command classifiers (v4)
GRAPH_CONTACT_RE = re.compile(
    r"(?:^|[;&|(\s])(?:rtk\s+)?(?:just\s+(?:path|graph|hubs|neighbors|update-graph)\b|"
    r"graphify\s+(?:query|path|god-nodes|explain|update)\b)",
    re.IGNORECASE,
)
GRAPH_UPDATE_RE = re.compile(
    r"(?:^|[;&|(\s])(?:rtk\s+)?(?:just\s+update-graph\b|graphify\s+update\b)",
    re.IGNORECASE,
)
AUDIT_RE = re.compile(
    r"(?:^|[;&|(\s])(?:rtk\s+)?just\s+audit\b",
    re.IGNORECASE,
)
UNANCHORED_SEARCH_RE = re.compile(
    r"(?:^|[;&|(\s])(?:rg\b|fd\b|grep\b)",
    re.IGNORECASE,
)

GRAPH_TOOL_MARKERS = (
    "query_graph", "get_node", "get_neighbors", "god_nodes",
    "shortest_path", "graph_stats", "get_community",
)
SEARCH_TOOLS = {
    "grep", "grep_search", "glob", "glob_file_search",
    "codebase_search", "find_by_name",
}
SHELL_TOOLS = {
    "run_command", "bash", "execute_command", "powershell",
    "terminal", "exec", "shell",
}
READ_TOOLS = {
    "view_file", "readfile", "read_file", "view", "cat", "get_content", "read",
}
WRITE_TOOLS = {
    "write_to_file", "writefile", "write_file", "write", "create_file",
}
EDIT_TOOLS = {
    "replace_file_content", "editfile", "edit_file", "edit",
    "str_replace_editor", "strreplace", "apply_patch", "applypatch",
    "multiedit", "multi_edit", "notebookedit", "notebook_edit",
    "search_replace",
}
STOP_EVENTS = {"stop", "sessionend", "sessionstart"}  # sessionstart ignored in inspect


def allow(reason: str = "", *, agent_message: str = "") -> dict:
    res = {"decision": "allow", "permission": "allow"}
    if reason:
        res["reason"] = reason
    if agent_message:
        res["agent_message"] = agent_message
        res["user_message"] = agent_message
        res["additional_context"] = agent_message
    return res


def deny(reason: str) -> dict:
    return {
        "decision": "deny",
        "permission": "deny",
        "reason": reason,
        "agent_message": reason,
        "user_message": reason,
    }


_CONV_ID_KEYS = (
    "conversationId", "conversation_id",
    "session_id", "sessionId",
    "composerId", "composer_id",
    "chat_id", "chatId",
    "agent_id", "agentId",
)


def _id_from_map(m) -> str:
    if not isinstance(m, dict):
        return ""
    for key in _CONV_ID_KEYS:
        val = m.get(key)
        if val:
            return str(val)
    return ""


def _stable_fallback_id() -> str:
    """Repo-root + TTL window. Cursor wraps each hook in a short-lived
    shell, so os.getppid() changes every call and cannot key session state."""
    root = find_repo_root()
    root_key = str(root).lower() if root else (os.getcwd() or "unknown")
    window = int(time.time() // STATE_TTL_SECONDS)
    digest = hashlib.sha256(root_key.encode("utf-8")).hexdigest()[:12]
    return f"win{window}_{digest}"


def resolve_conv_id(payload: dict) -> str:
    found = _id_from_map(payload)
    if found:
        return found
    for nest in ("session", "conversation", "context", "metadata"):
        found = _id_from_map(payload.get(nest) or {})
        if found:
            return found
    return _stable_fallback_id()


def _canon_tool(name: str) -> str:
    return (name or "").lower().replace("-", "_").replace(" ", "_")


def _raw_tool_name(payload: dict, tool_call: dict) -> str:
    return (
        tool_call.get("name") or tool_call.get("tool_name")
        or payload.get("name") or payload.get("tool_name") or payload.get("toolName")
        or payload.get("mcp_tool") or payload.get("mcpTool")
        or payload.get("mcp_tool_name") or ""
    )


def extract_tool_name(payload: dict, tool_call: dict) -> str:
    """Canonical tool name without MCP server prefix, so SHELL/EDIT sets match."""
    return _canon_tool(_raw_tool_name(payload, tool_call))


def _graph_lookup_name(payload: dict, tool_call: dict) -> str:
    """Server-prefixed name used only for is_graph_tool matching."""
    raw = _raw_tool_name(payload, tool_call)
    server = (
        payload.get("server") or payload.get("mcp_server")
        or payload.get("mcpServer") or ""
    )
    return _canon_tool(f"{server} {raw}".strip())


def detect_harness(payload=None) -> str:
    p = payload if isinstance(payload, dict) else {}
    if p.get("cursor_version"):
        return "cursor"
    if os.environ.get("CLAUDE_PROJECT_DIR") or ("permission_mode" in p):
        return "claude"
    return "antigravity"


def emit_result(result: dict, harness: str, hook_event: str) -> None:
    """Write harness-specific JSON and exit. Claude deny uses exit 2 as a
    schema-proof block; Cursor/Antigravity keep the v4.1 superset JSON."""
    denied = result.get("decision") == "deny" or result.get("permission") == "deny"
    reason = result.get("reason") or result.get("agent_message") or ""
    if harness == "claude":
        if hook_event in ("stop", "sessionend"):
            msg = result.get("followup_message") or result.get("reason") or ""
            if msg and (result.get("followup_message") or result.get("decision") == "block"):
                print(json.dumps({"decision": "block", "reason": msg}))
            else:
                print("{}")
            sys.exit(0)
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny" if denied else "allow",
                "permissionDecisionReason": reason,
            }
        }
        print(json.dumps(out))
        if denied:
            print(reason, file=sys.stderr)
            sys.exit(2)
        sys.exit(0)
    print(json.dumps(result))
    sys.exit(0)


def _norm_path(p: str) -> str:
    if not p:
        return ""
    try:
        return os.path.normcase(os.path.abspath(p))
    except Exception:
        return p.replace("\\", "/").lower()


# --- Repo / graph discovery ----------------------------------------------------
def find_repo_root():
    """Walk cwd (then the guard's parent tree) for graph.json or this repo's justfile.
    AGENT_GUARD_GRAPH_ROOT overrides discovery (used by the test suite)."""
    override = os.environ.get("AGENT_GUARD_GRAPH_ROOT")
    if override:
        p = Path(override)
        return p if p.exists() else None
    starts = []
    try:
        starts.append(Path.cwd().resolve())
    except Exception:
        pass
    try:
        starts.append(Path(__file__).resolve().parent.parent)
    except Exception:
        pass
    seen = set()
    for start in starts:
        cur = start
        for _ in range(10):
            key = str(cur)
            if key in seen:
                break
            seen.add(key)
            if (cur / "graphify-out" / "graph.json").is_file():
                return cur
            if (cur / "justfile").is_file() and (cur / "configs" / "agents").is_dir():
                return cur
            if cur.parent == cur:
                break
            cur = cur.parent
    return None


def graph_exists() -> bool:
    root = find_repo_root()
    return bool(root and (root / "graphify-out" / "graph.json").is_file())


def session_log_path():
    override = os.environ.get("AGENT_GUARD_LOG")
    if override:
        return Path(override)
    root = find_repo_root()
    if not root:
        return None
    return root / "graphify-out" / "session-log.jsonl"


def append_session_log(entry: dict) -> None:
    try:
        path = session_log_path()
        if path is None:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def is_graph_tool(name: str) -> bool:
    n = (name or "").lower().replace("-", "_")
    return any(marker in n for marker in GRAPH_TOOL_MARKERS)


def normalize_event(payload: dict) -> str:
    raw = str(
        payload.get("hook_event_name")
        or payload.get("hookEventName")
        or payload.get("event")
        or ""
    ).lower()
    return re.sub(r"[-_]", "", raw)


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
    return {
        "ts": time.time(),
        "reads": [],
        "strikes": {},
        "graph_contact": False,
        "edited": False,
        "edit_files": [],
        "did_update_graph": False,
        "did_audit": False,
        "last_edit": None,
        "logged_keys": False,
    }


def _read_state_file(path: Path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _fallback_window_parts(conv_id: str):
    m = re.match(r"^win(\d+)_([0-9a-fA-F]+)$", conv_id or "")
    if not m:
        return None
    return int(m.group(1)), m.group(2)


def _union_list(a, b):
    seen = []
    for x in list(a or []) + list(b or []):
        if x not in seen:
            seen.append(x)
    return seen


def _merge_states(disk: dict, incoming: dict) -> dict:
    """Union-merge so a parallel hook cannot clobber strikes / flags."""
    out = dict(incoming)
    out["reads"] = _union_list(disk.get("reads"), incoming.get("reads"))
    out["edit_files"] = _union_list(disk.get("edit_files"), incoming.get("edit_files"))
    strikes = dict(disk.get("strikes") or {})
    strikes.update(incoming.get("strikes") or {})
    out["strikes"] = strikes
    for flag in ("graph_contact", "edited", "did_update_graph", "did_audit", "logged_keys"):
        out[flag] = bool(disk.get(flag)) or bool(incoming.get(flag))
    # Ephemeral metric flag: the writer of this save owns the value.
    out["thrash_hit"] = bool(incoming.get("thrash_hit"))
    d_le = disk.get("last_edit") if isinstance(disk.get("last_edit"), dict) else {}
    i_le = incoming.get("last_edit") if isinstance(incoming.get("last_edit"), dict) else {}
    d_ts = float(d_le.get("ts") or 0)
    i_ts = float(i_le.get("ts") or 0)
    if d_ts > i_ts:
        out["last_edit"] = d_le
    else:
        out["last_edit"] = i_le or d_le or None
    try:
        out["ts"] = min(float(disk.get("ts") or time.time()),
                        float(incoming.get("ts") or time.time()))
    except (TypeError, ValueError):
        out["ts"] = incoming.get("ts") or time.time()
    return out


def load_state(conv_id: str) -> dict:
    state_file = get_state_file(conv_id)
    if state_file.exists():
        state = _read_state_file(state_file)
        if isinstance(state, dict):
            if time.time() - float(state.get("ts", 0) or 0) > STATE_TTL_SECONDS:
                return fresh_state()
            return state
    parts = _fallback_window_parts(conv_id)
    if parts:
        window, digest = parts
        prev = get_state_file(f"win{window - 1}_{digest}")
        if prev.exists():
            state = _read_state_file(prev)
            if isinstance(state, dict):
                if time.time() - float(state.get("ts", 0) or 0) <= STATE_TTL_SECONDS:
                    return state
    return fresh_state()


def save_state(conv_id: str, state: dict) -> None:
    try:
        path = get_state_file(conv_id)
        disk = _read_state_file(path) if path.exists() else None
        merged = _merge_states(disk, state) if isinstance(disk, dict) else dict(state)
        merged["ts"] = merged.get("ts") or time.time()
        with open(path, "w", encoding="utf-8") as f:
            json.dump(merged, f, ensure_ascii=False)
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


def record_shell_graph_events(cmd: str, state: dict) -> None:
    if not cmd:
        return
    if GRAPH_CONTACT_RE.search(cmd):
        state["graph_contact"] = True
    if GRAPH_UPDATE_RE.search(cmd):
        state["did_update_graph"] = True
        state["graph_contact"] = True
    if AUDIT_RE.search(cmd):
        state["did_audit"] = True


# --- Inspectors -----------------------------------------------------------------
def inspect_run_command(args: dict, conv_id: str) -> dict:
    cmd = args.get("CommandLine") or args.get("command") or args.get("cmd") or args.get("script") or ""

    # Gate 1: destructive commands — unconditional hard deny (no one-strike).
    reason = find_dangerous(cmd)
    if reason:
        return deny(f"Agent Guard [Safety Block]: {reason} -> '{cmd[:70]}...'")

    state = load_state(conv_id)
    record_shell_graph_events(cmd, state)

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

    # Gate 4 (v4): unanchored search before any graph query.
    if graph_exists() and not state.get("graph_contact") and UNANCHORED_SEARCH_RE.search(cmd):
        if first_strike(state, "graph-gate:search"):
            save_state(conv_id, state)
            return deny(
                "Agent Guard [Graph-First]: unanchored search while graphify-out/graph.json exists. "
                "Query the graph first: `just hubs` or `just path <a> <b>`, then scoped "
                "`rg -n <pattern> <file>` (retry passes; one-strike)."
            )

    save_state(conv_id, state)
    return allow()


def inspect_search_tool(conv_id: str) -> dict:
    """Grep/Glob/codebase_search without prior graph contact (v4 graph-gate)."""
    state = load_state(conv_id)
    if graph_exists() and not state.get("graph_contact"):
        if first_strike(state, "graph-gate:search"):
            save_state(conv_id, state)
            return deny(
                "Agent Guard [Graph-First]: unanchored search while graphify-out/graph.json exists. "
                "Query the graph first: `just hubs` or `just path <a> <b>`, then scoped "
                "`rg -n <pattern> <file>` (retry passes; one-strike)."
            )
    save_state(conv_id, state)
    return allow()


def inspect_graph_tool(conv_id: str) -> dict:
    state = load_state(conv_id)
    state["graph_contact"] = True
    save_state(conv_id, state)
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

    result = allow()
    last = state.get("last_edit") or {}
    last_path = last.get("path") or ""
    last_ts = float(last.get("ts") or 0)
    if last_path and _norm_path(last_path) == _norm_path(str(target_path)):
        if time.time() - last_ts <= THRASH_WINDOW_SECONDS:
            msg = (
                "Agent Guard [Edit Verification]: redundant view after edit on "
                f"'{path_obj.name}'. Treat the edit tool's success snippet as "
                "verification. Prefer content-addressed edits or Bottom-Up line edits; "
                "re-read only on edit failure, ambiguous result, or external rewrite."
            )
            result = allow(reason=msg, agent_message=msg)
            state["thrash_hit"] = True

    save_state(conv_id, state)
    return result


def inspect_write_to_file(args: dict) -> dict:
    target_file = args.get("TargetFile") or args.get("path") or args.get("file_path") or ""
    metadata = args.get("ArtifactMetadata")

    if metadata and target_file and "brain" not in target_file.lower():
        return deny(
            "Agent Guard [Workspace Edit Invariant]: Do NOT use write_to_file with ArtifactMetadata "
            "on workspace project files. Use replace_file_content for atomic surgical edits."
        )
    return allow()


def _edit_target(args: dict) -> str:
    return (
        args.get("TargetFile") or args.get("path") or args.get("file_path")
        or args.get("target_notebook") or args.get("AbsolutePath") or "unknown"
    )


def inspect_edit_gate(args: dict, conv_id: str, metadata_check: bool = False) -> dict:
    """v4 edit-gate: require graph contact before the first edit; pinpoint = one file."""
    if metadata_check:
        md_result = inspect_write_to_file(args)
        if md_result.get("decision") == "deny":
            return md_result

    target = _edit_target(args)
    state = load_state(conv_id)
    files = list(state.get("edit_files") or [])
    unique = []
    for f in files:
        if f not in unique:
            unique.append(f)

    if graph_exists() and not state.get("graph_contact"):
        if not unique:
            if first_strike(state, "edit-gate"):
                save_state(conv_id, state)
                return deny(
                    "Agent Guard [Graph-First]: graph exists but no graph query before first edit. "
                    "Run `just path <a> <b>` or `get_node(label=…)` to scope blast radius "
                    "(retry of the SAME file passes as pinpoint; one-strike)."
                )
        elif target not in unique:
            if first_strike(state, f"edit-gate:multi:{target}"):
                save_state(conv_id, state)
                return deny(
                    "Agent Guard [Graph-First]: multi-file edit without graph query. "
                    "Pinpoint exception is ONE file. Run `just path` first "
                    f"(retry of '{Path(str(target)).name}' passes; one-strike)."
                )

    state["edited"] = True
    if target not in files:
        files.append(target)
    state["edit_files"] = files
    state["reads"] = []
    state["last_edit"] = {"path": str(target), "ts": time.time()}
    save_state(conv_id, state)
    return allow()


def inspect_batch_end(conv_id: str) -> dict:
    """stop/sessionEnd: warn once if edits happened without update-graph + audit."""
    state = load_state(conv_id)
    edited = bool(state.get("edited"))
    updated = bool(state.get("did_update_graph"))
    audited = bool(state.get("did_audit"))
    result = allow()
    if edited and (not updated or not audited):
        missing = []
        if not updated:
            missing.append("`just update-graph`")
        if not audited:
            missing.append("`just audit`")
        msg = (
            "Agent Guard [Batch End]: edits recorded this session but "
            + " and ".join(missing)
            + " not run. Run them before reporting done. "
            "just audit PASS proves no regression, not that a fix works (Done contract)."
        )
        if first_strike(state, "batch-end"):
            result["reason"] = msg
            result["followup_message"] = msg
            result["additional_context"] = msg
            result["agent_message"] = msg
        save_state(conv_id, state)
        return result
    save_state(conv_id, state)
    return result


# --- Entry point ------------------------------------------------------------------
def _extract_args(payload: dict, tool_call: dict) -> dict:
    args = (
        tool_call.get("args") or tool_call.get("arguments") or tool_call.get("parameters")
        or payload.get("args") or payload.get("tool_input") or payload.get("input") or {}
    )
    if not args:
        args = {}
    if not args.get("CommandLine") and not args.get("command"):
        for key in ("command", "CommandLine", "cmd"):
            if payload.get(key):
                args = dict(args)
                args[key] = payload.get(key)
                break
    return args


def main() -> None:
    raw_input_data = ""
    conv_id = "default"
    tool_name = ""
    hook_event = ""
    harness = detect_harness()
    result = allow()
    try:
        raw_input_data = sys.stdin.read()
        if not raw_input_data or not raw_input_data.lstrip('\ufeff').strip():
            emit_result(allow(), harness, "")
            return
        payload = json.loads(raw_input_data.lstrip('\ufeff').strip())
        harness = detect_harness(payload)

        tool_call = payload.get("toolCall") or payload.get("tool_call") or payload
        tool_name = extract_tool_name(payload, tool_call)
        graph_name = _graph_lookup_name(payload, tool_call)
        args = _extract_args(payload, tool_call)
        conv_id = resolve_conv_id(payload)
        hook_event = normalize_event(payload)

        gc_stale_state_files()

        if hook_event in ("stop", "sessionend") and payload.get("stop_hook_active"):
            result = allow()
        elif hook_event in ("stop", "sessionend"):
            result = inspect_batch_end(conv_id)
        elif is_graph_tool(tool_name) or is_graph_tool(graph_name):
            result = inspect_graph_tool(conv_id)
        elif tool_name in SHELL_TOOLS:
            result = inspect_run_command(args, conv_id)
        elif tool_name in SEARCH_TOOLS:
            result = inspect_search_tool(conv_id)
        elif tool_name in READ_TOOLS:
            result = inspect_view_file(args, conv_id)
        elif tool_name in WRITE_TOOLS:
            result = inspect_edit_gate(args, conv_id, metadata_check=True)
        elif tool_name in EDIT_TOOLS:
            result = inspect_edit_gate(args, conv_id, metadata_check=False)
        else:
            result = allow()

        try:
            st = load_state(conv_id)
            entry = {
                "ts": int(time.time()),
                "conv": conv_id,
                "event": hook_event or "preToolUse",
                "tool": (tool_name or "")[:80],
                "decision": result.get("decision"),
                "graph_contact": bool(st.get("graph_contact")),
                "edited": bool(st.get("edited")),
                "denied": result.get("decision") == "deny",
                "thrash": bool(st.get("thrash_hit")),
                "harness": harness,
            }
            if not st.get("logged_keys"):
                entry["keys"] = sorted(str(k) for k in payload.keys())[:40]
                st["logged_keys"] = True
            append_session_log(entry)
            if st.get("thrash_hit"):
                st["thrash_hit"] = False
            save_state(conv_id, st)
        except Exception:
            pass

        emit_result(result, harness, hook_event)
        return
    except Exception as e:
        try:
            reason = find_dangerous(raw_input_data)
        except Exception:
            reason = None
        if reason:
            emit_result(
                deny(f"Agent Guard [Safety Block/fallback]: {reason} (raw payload scan)"),
                harness,
                hook_event,
            )
        else:
            emit_result(allow(f"Agent Guard warning: {str(e)}"), harness, hook_event)


if __name__ == "__main__":
    main()
