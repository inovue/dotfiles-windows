#!/usr/bin/env python3
"""
Agent Guard: Deterministic Cybernetic Governor & Lifecycle Hook for AI Agents.
Validates tool invocations, enforces safety invariants, prevents destructive operations,
and deterministically limits token waste (read budgets & modern CLI invariants).
"""
import sys
import json
import re
import os
import tempfile
from pathlib import Path

# 1. Critical destructive patterns (Hard Deny)
DANGEROUS_PATTERNS = [
    (r"\bformat\s+[a-zA-Z]:", "Disk formatting command detected"),
    (r"\bdiskpart\b", "Disk partitioning command detected"),
    (r"\brmdir\s+/[sS]\s+/[qQ]\s+[cC]:\\(?:\s|$)", "Root drive recursive wipe detected"),
    (r"\brm\s+-rf\s+/[*\s]*$", "Root filesystem wipe detected"),
    (r"git\s+push\s+[^;|\n]*--force[^\n]*\b(?:main|master)\b", "Force push to protected branch blocked"),
    (r"(?:curl|iwr|Invoke-WebRequest)[^\n|]*\|\s*(?:iex|Invoke-Expression)", "Unverified remote script execution pipe blocked"),
]

# 2. Slow PowerShell cmdlets that violate Modern CLI Invariants (Deny with Guidance)
SLOW_CLI_PATTERNS = [
    (r"\bGet-ChildItem\b[^\n|]*-Recurse\b", "Slow PowerShell pipeline detected: Use 'fd <pattern>' instead of 'Get-ChildItem -Recurse'"),
    (r"\bSelect-String\b", "Slow PowerShell cmdlet detected: Use 'rg -n <pattern>' instead of 'Select-String'"),
]

MAX_READ_BUDGET_PER_CONVERSATION = 4
MAX_UNSLICED_LINE_COUNT = 120

def get_state_file(conv_id: str) -> Path:
    temp_dir = Path(tempfile.gettempdir()) / "agy_agent_guard"
    temp_dir.mkdir(parents=True, exist_ok=True)
    safe_id = re.sub(r"[^a-zA-Z0-9_-]", "_", conv_id or "default")
    return temp_dir / f"session_{safe_id}.json"

def load_state(conv_id: str) -> dict:
    state_file = get_state_file(conv_id)
    if state_file.exists():
        try:
            with open(state_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"reads": [], "edits": []}

def save_state(conv_id: str, state: dict):
    state_file = get_state_file(conv_id)
    try:
        with open(state_file, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False)
    except Exception:
        pass

def inspect_run_command(args: dict) -> dict:
    cmd = args.get("CommandLine") or args.get("command") or args.get("cmd") or args.get("script") or ""
    for pattern, reason in DANGEROUS_PATTERNS:
        if re.search(pattern, cmd, re.IGNORECASE):
            return {
                "decision": "deny",
                "reason": f"Agent Guard [Safety Block]: {reason} -> '{cmd[:70]}...'"
            }
    for pattern, reason in SLOW_CLI_PATTERNS:
        if re.search(pattern, cmd, re.IGNORECASE):
            return {
                "decision": "deny",
                "reason": f"Agent Guard [Modern CLI Invariant]: {reason}"
            }
    return {"decision": "allow"}

def inspect_view_file(args: dict, conv_id: str) -> dict:
    target_path = args.get("AbsolutePath") or args.get("TargetFile") or args.get("path") or args.get("file_path") or args.get("filename") or ""
    start_line = args.get("StartLine") or args.get("start_line") or args.get("offset")
    end_line = args.get("EndLine") or args.get("end_line") or args.get("limit")

    if not target_path:
        return {"decision": "allow"}

    path_obj = Path(target_path)
    file_name = path_obj.name.lower()

    # Skill documentation and rule entrypoints are exempt from strict line caps
    is_exempt = file_name in ["skill.md", "agents.md", "claude.md", ".cursorrules", "gemini.md", "hooks.json"] or "skills" in target_path.lower()

    # Gate 1: Check un-sliced whole-file read on large project files
    if not is_exempt and start_line is None and end_line is None and path_obj.is_file():
        try:
            line_count = sum(1 for _ in open(path_obj, "r", encoding="utf-8", errors="ignore"))
            if line_count > MAX_UNSLICED_LINE_COUNT:
                return {
                    "decision": "deny",
                    "reason": f"Agent Guard [Read Budget Invariant]: Un-sliced read of '{path_obj.name}' ({line_count} lines > {MAX_UNSLICED_LINE_COUNT}) blocked. Use StartLine/EndLine or Graphify loc=Lxx / rg -n snippets."
                }
        except Exception:
            pass

    # Gate 2: Read budget count tracking
    state = load_state(conv_id)
    read_list = state.get("reads", [])

    if target_path not in read_list and not is_exempt:
        if len(read_list) >= MAX_READ_BUDGET_PER_CONVERSATION:
            return {
                "decision": "deny",
                "reason": f"Agent Guard [Read Budget Invariant]: Read limit exceeded ({len(read_list)} files read). You have gathered sufficient context—synthesize markdown findings or use targeted 'rg -n' / 'ast-grep' instead."
            }
        read_list.append(target_path)
        state["reads"] = read_list
        save_state(conv_id, state)

    return {"decision": "allow"}

def inspect_write_to_file(args: dict) -> dict:
    target_file = args.get("TargetFile") or args.get("path") or args.get("file_path") or ""
    metadata = args.get("ArtifactMetadata")
    
    # If writing to workspace project files (not in brain/artifact folder) with ArtifactMetadata
    if metadata and target_file and "brain" not in target_file.lower():
        return {
            "decision": "deny",
            "reason": "Agent Guard [Workspace Edit Invariant]: Do NOT use write_to_file with ArtifactMetadata on workspace project files. Use replace_file_content for atomic surgical edits."
        }
    return {"decision": "allow"}

def main():
    try:
        raw_input = sys.stdin.read()
        if not raw_input:
            print(json.dumps({"decision": "allow"}))
            return

        raw_input = raw_input.lstrip('\ufeff').strip()
        if not raw_input:
            print(json.dumps({"decision": "allow"}))
            return

        payload = json.loads(raw_input)
        tool_call = payload.get("toolCall") or payload.get("tool_call") or payload
        tool_name = (tool_call.get("name") or tool_call.get("tool_name") or payload.get("name") or "").lower()
        args = tool_call.get("args") or tool_call.get("arguments") or tool_call.get("parameters") or payload.get("args") or payload.get("input") or {}
        conv_id = payload.get("conversationId") or payload.get("conversation_id") or "default"

        if tool_name in ["run_command", "bash", "execute_command", "powershell", "terminal", "exec"]:
            res = inspect_run_command(args)
            print(json.dumps(res))
            return

        if tool_name in ["view_file", "readfile", "read_file", "view", "cat", "get_content"]:
            res = inspect_view_file(args, conv_id)
            print(json.dumps(res))
            return

        if tool_name in ["write_to_file", "writefile", "write_file", "write", "create_file"]:
            res = inspect_write_to_file(args)
            print(json.dumps(res))
            return

        if tool_name in ["replace_file_content", "editfile", "edit_file", "edit", "str_replace_editor"]:
            # On file edits, reset read budget for the next iteration cycle
            state = load_state(conv_id)
            state["reads"] = []
            save_state(conv_id, state)
            print(json.dumps({"decision": "allow"}))
            return

        # Default: Allow valid operations
        print(json.dumps({"decision": "allow"}))
    except Exception as e:
        # Fail open with warning log to prevent locking the agent loop on parser glitches
        print(json.dumps({"decision": "allow", "reason": f"Agent Guard warning: {str(e)}"}))

if __name__ == "__main__":
    main()
