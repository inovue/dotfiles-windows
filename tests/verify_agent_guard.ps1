#Requires -Version 5.1
<#
.SYNOPSIS
    Fail-to-pass tests for agent_guard.py v4.2 (session identity, MCP, thrash, Claude ACI, merge).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = Split-Path -Parent $PSScriptRoot
$passedCount = 0
$failedCount = 0

function Assert-Test {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Details = ""
    )
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passedCount++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkRed }
        $script:failedCount++
    }
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "  Agent Guard v4.2 Session / Thrash / Claude Regression  " -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

$guardScript = Join-Path $rootDir "scripts\agent_guard.py"
$tempTestDir = Join-Path $env:TEMP "guard_v41_$(Get-Random)"
New-Item -Path $tempTestDir -ItemType Directory -Force | Out-Null

try {
    $testJsonFile = Join-Path $tempTestDir "guard_test.json"
    $guardPyEsc = $guardScript.Replace('\', '/')
    $testJsonEsc = $testJsonFile.Replace('\', '/')

    function Invoke-GuardHook {
        param([hashtable]$Payload)
        $json = $Payload | ConvertTo-Json -Compress -Depth 8
        [System.IO.File]::WriteAllText($testJsonFile, $json, [System.Text.Encoding]::UTF8)
        return (python -c "import subprocess; p = subprocess.run(['python', '$guardPyEsc'], input=open('$testJsonEsc', 'rb').read(), capture_output=True); print(p.stdout.decode('utf-8'))" 2>&1 | Out-String)
    }

    $v4Root = Join-Path $tempTestDir "graph_root"
    $v4GraphDir = Join-Path $v4Root "graphify-out"
    New-Item -Path $v4GraphDir -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $v4GraphDir "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $v4Log = Join-Path $tempTestDir "session-log.jsonl"
    $env:AGENT_GUARD_GRAPH_ROOT = $v4Root
    $env:AGENT_GUARD_LOG = $v4Log

    # --- P0: fallback conv_id is stable without conversationId (ppid must not be used)
    $fbRoot = Join-Path $tempTestDir "fallback_root"
    $fbGraph = Join-Path $fbRoot "graphify-out"
    New-Item -Path $fbGraph -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fbGraph "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $env:AGENT_GUARD_GRAPH_ROOT = $fbRoot
    $env:AGENT_GUARD_LOG = (Join-Path $tempTestDir "fallback-log.jsonl")

    $rgNoId = @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } } }
    $fbDeny = Invoke-GuardHook $rgNoId
    $fbRetry = Invoke-GuardHook $rgNoId
    Assert-Test -Name "v4.1 fallback conv_id: first unanchored rg denied" -Condition ($fbDeny -match '"decision":\s*"deny"' -and $fbDeny -match 'user_message') -Details ($fbDeny.Trim())
    Assert-Test -Name "v4.1 fallback conv_id: retry allowed (one-strike survives missing conversationId)" -Condition ($fbRetry -match '"decision":\s*"allow"') -Details ($fbRetry.Trim())

    # --- P0: Cursor conversation_id (snake_case) keys the same session
    $env:AGENT_GUARD_GRAPH_ROOT = $v4Root
    $env:AGENT_GUARD_LOG = $v4Log
    $snake = "test_snake_$(Get-Random)"
    $rgSnake = @{ toolCall = @{ name = "Grep"; args = @{ pattern = "TODO" } }; conversation_id = $snake }
    $snake1 = Invoke-GuardHook $rgSnake
    $snake2 = Invoke-GuardHook $rgSnake
    Assert-Test -Name "v4.1 conversation_id field: first Grep denied" -Condition ($snake1 -match '"decision":\s*"deny"') -Details ($snake1.Trim())
    Assert-Test -Name "v4.1 conversation_id field: retry allowed" -Condition ($snake2 -match '"decision":\s*"allow"') -Details ($snake2.Trim())

    # --- P0: deny payload includes Cursor ACI fields
    Assert-Test -Name "v4.1 deny emits user_message and agent_message" -Condition ($snake1 -match '"user_message"' -and $snake1 -match '"agent_message"') -Details ($snake1.Trim())

    # --- P0: beforeMCPExecution records graph_contact, subsequent edit allowed
    $mcpConv = "test_mcp_$(Get-Random)"
    $mcpRes = Invoke-GuardHook @{
        hook_event_name = "beforeMCPExecution"
        tool_name       = "query_graph"
        tool_input      = @{ question = "deploy"; token_budget = 1200 }
        conversationId  = $mcpConv
    }
    $editAfterMcp = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ path = "scripts/agent_guard.py" } }
        conversationId = $mcpConv
    }
    Assert-Test -Name "v4.1 beforeMCPExecution query_graph is allowed" -Condition ($mcpRes -match '"decision":\s*"allow"') -Details ($mcpRes.Trim())
    Assert-Test -Name "v4.1 MCP graph contact allows subsequent edit" -Condition ($editAfterMcp -match '"decision":\s*"allow"') -Details ($editAfterMcp.Trim())

    # Cursor MCP server-prefixed tool name
    $mcpConv2 = "test_mcp2_$(Get-Random)"
    $mcpPrefixed = Invoke-GuardHook @{
        hook_event_name = "beforeMCPExecution"
        server          = "user-graphify"
        tool_name       = "query_graph"
        conversationId  = $mcpConv2
    }
    $edit2 = Invoke-GuardHook @{
        tool_name      = "Edit"
        tool_input     = @{ path = "configs/agents/GLOBAL_RULES.md" }
        conversationId = $mcpConv2
    }
    Assert-Test -Name "v4.1 namespaced MCP query_graph records graph contact" -Condition ($mcpPrefixed -match '"decision":\s*"allow"' -and $edit2 -match '"decision":\s*"allow"') -Details ($edit2.Trim())

    # --- P3: read-after-edit is allow + guidance (not deny)
    $thrashConv = "test_thrash_$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "query_graph"; args = @{ question = "hubs" } }
        conversationId = $thrashConv
    }
    $targetFile = Join-Path $tempTestDir "edited.txt"
    [System.IO.File]::WriteAllText($targetFile, "hello`n", [System.Text.Encoding]::UTF8)
    $targetEsc = $targetFile.Replace('\', '/')
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ path = $targetEsc } }
        conversationId = $thrashConv
    }
    $thrashRes = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $targetEsc } }
        conversationId = $thrashConv
    }
    $thrashAllow = ($thrashRes -match '"decision":\s*"allow"')
    $thrashGuide = ($thrashRes -match 'Edit Verification')
    Assert-Test -Name "v4.1 thrash: read-after-edit is allowed (not denied)" -Condition $thrashAllow -Details ($thrashRes.Trim())
    Assert-Test -Name "v4.1 thrash: allow includes Edit Verification guidance" -Condition $thrashGuide -Details ($thrashRes.Trim())

    $logText = ""
    if (Test-Path $v4Log) {
        $logText = [System.IO.File]::ReadAllText($v4Log, [System.Text.Encoding]::UTF8)
    }
    Assert-Test -Name "v4.1 session-log records thrash=true" -Condition ($logText -match '"thrash":\s*true') -Details $v4Log

    function Invoke-GuardProc {
        param([hashtable]$Payload)
        $json = $Payload | ConvertTo-Json -Compress -Depth 8
        [System.IO.File]::WriteAllText($testJsonFile, $json, [System.Text.Encoding]::UTF8)
        $raw = python -c "import subprocess, json; p = subprocess.run(['python', '$guardPyEsc'], input=open('$testJsonEsc', 'rb').read(), capture_output=True); print(json.dumps({'stdout': p.stdout.decode('utf-8'), 'stderr': p.stderr.decode('utf-8'), 'code': p.returncode}))"
        return $raw | ConvertFrom-Json
    }

    # --- v4.2: Claude Code output adapter (exit 2 + hookSpecificOutput)
    $env:CLAUDE_PROJECT_DIR = $rootDir
    $claudeDangerConv = "test_claude_deny_$(Get-Random)"
    $claudeDanger = Invoke-GuardProc @{
        tool_name      = "Bash"
        tool_input     = @{ command = "rm -rf /" }
        conversationId = $claudeDangerConv
        hook_event_name = "PreToolUse"
    }
    Assert-Test -Name "v4.2 Claude deny: permissionDecision deny" -Condition ($claudeDanger.stdout -match 'hookSpecificOutput' -and $claudeDanger.stdout -match '"permissionDecision":\s*"deny"') -Details ($claudeDanger.stdout)
    Assert-Test -Name "v4.2 Claude deny: exit code 2" -Condition ([int]$claudeDanger.code -eq 2) -Details ("exit=" + $claudeDanger.code)
    Assert-Test -Name "v4.2 Claude deny: no top-level decision key" -Condition ($claudeDanger.stdout -notmatch '"decision"') -Details ($claudeDanger.stdout)

    $claudeSafeConv = "test_claude_safe_$(Get-Random)"
    $claudeSafe = Invoke-GuardProc @{
        tool_name       = "Bash"
        tool_input      = @{ command = "just audit" }
        conversationId  = $claudeSafeConv
        hook_event_name = "PreToolUse"
    }
    Assert-Test -Name "v4.2 Claude allow: exit 0" -Condition ([int]$claudeSafe.code -eq 0) -Details ("exit=" + $claudeSafe.code + " out=" + $claudeSafe.stdout)
    Assert-Test -Name "v4.2 Claude allow: no top-level decision key" -Condition ($claudeSafe.stdout -notmatch '"decision"') -Details ($claudeSafe.stdout)

    $claudeStopLoop = Invoke-GuardProc @{
        hook_event_name  = "Stop"
        stop_hook_active = $true
        conversationId   = $claudeSafeConv
    }
    Assert-Test -Name "v4.2 Claude stop_hook_active short-circuits (no block)" -Condition ([int]$claudeStopLoop.code -eq 0 -and $claudeStopLoop.stdout -notmatch '"decision":\s*"block"') -Details ($claudeStopLoop.stdout)

    $claudeEditConv = "test_claude_stop_$(Get-Random)"
    $null = Invoke-GuardHook @{
        tool_name      = "Edit"
        tool_input     = @{ path = "scripts/foo.ps1" }
        conversationId = $claudeEditConv
    }
    $null = Invoke-GuardHook @{
        tool_name      = "Edit"
        tool_input     = @{ path = "scripts/foo.ps1" }
        conversationId = $claudeEditConv
    }
    $claudeStop = Invoke-GuardProc @{
        hook_event_name = "Stop"
        conversationId  = $claudeEditConv
    }
    Assert-Test -Name "v4.2 Claude Stop batch-end uses decision:block" -Condition ($claudeStop.stdout -match '"decision":\s*"block"' -and $claudeStop.stdout -match 'just update-graph') -Details ($claudeStop.stdout)

    Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue

    # --- v4.2: MultiEdit / NotebookEdit hit edit-gate
    $meConv = "test_multiedit_$(Get-Random)"
    $meDeny = Invoke-GuardHook @{
        tool_name      = "MultiEdit"
        tool_input     = @{ path = "scripts/foo.ps1" }
        conversationId = $meConv
    }
    $meRetry = Invoke-GuardHook @{
        tool_name      = "MultiEdit"
        tool_input     = @{ path = "scripts/foo.ps1" }
        conversationId = $meConv
    }
    $nbDeny = Invoke-GuardHook @{
        tool_name      = "NotebookEdit"
        tool_input     = @{ target_notebook = "scripts/bar.ipynb" }
        conversationId = $meConv
    }
    Assert-Test -Name "v4.2 MultiEdit edit-gate denies first edit without graph" -Condition ($meDeny -match '"decision":\s*"deny"') -Details ($meDeny.Trim())
    Assert-Test -Name "v4.2 MultiEdit pinpoint retry passes" -Condition ($meRetry -match '"decision":\s*"allow"') -Details ($meRetry.Trim())
    Assert-Test -Name "v4.2 NotebookEdit second file denied without graph" -Condition ($nbDeny -match '"decision":\s*"deny"') -Details ($nbDeny.Trim())

    # --- v4.2: save_state merge keeps a concurrently injected strike
    $mergeConv = "test_merge_$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "Grep"; args = @{ pattern = "TODO" } }
        conversationId = $mergeConv
    }
    $stateFile = Join-Path $env:TEMP ("agy_agent_guard\session_" + $mergeConv + ".json")
    $stateEsc = $stateFile.Replace('\', '/')
    python -c "import json; p='$stateEsc'; st=json.load(open(p,encoding='utf-8')); st.setdefault('strikes',{})['injected']=1; json.dump(st, open(p,'w',encoding='utf-8'))"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit" } }
        conversationId = $mergeConv
    }
    $mergeKeep = python -c "import json; st=json.load(open('$stateEsc',encoding='utf-8')); print('yes' if 'injected' in (st.get('strikes') or {}) else 'no')"
    Assert-Test -Name "v4.2 save_state merge preserves injected strike" -Condition ($mergeKeep.Trim() -eq "yes") -Details ($mergeKeep + " file=" + $stateFile)

    # --- v4.2: fallback window carry-over
    $winRoot = Join-Path $tempTestDir "win_root"
    New-Item -Path (Join-Path $winRoot "graphify-out") -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $winRoot "graphify-out\graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $env:AGENT_GUARD_GRAPH_ROOT = $winRoot
    $winPy = @"
import hashlib, json, os, time
from pathlib import Path
root = Path(os.environ['AGENT_GUARD_GRAPH_ROOT'])
window = int(time.time() // (2 * 60 * 60))
digest = hashlib.sha256(str(root).lower().encode('utf-8')).hexdigest()[:12]
prev = Path(os.environ['TEMP']) / 'agy_agent_guard' / ('session_win%d_%s.json' % (window - 1, digest))
prev.parent.mkdir(parents=True, exist_ok=True)
json.dump({
    'ts': time.time(), 'reads': [], 'strikes': {'graph-gate:search': time.time()},
    'graph_contact': False, 'edited': False, 'edit_files': [],
    'did_update_graph': False, 'did_audit': False, 'last_edit': None,
}, open(prev, 'w', encoding='utf-8'))
print(prev)
"@
    $winPyFile = Join-Path $tempTestDir "win_prev.py"
    [System.IO.File]::WriteAllText($winPyFile, $winPy, [System.Text.Encoding]::UTF8)
    $null = python $winPyFile
    $winCarry = Invoke-GuardHook @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } } }
    Assert-Test -Name "v4.2 fallback window carry-over: prev-window strike makes rg retry-pass" -Condition ($winCarry -match '"decision":\s*"allow"') -Details ($winCarry.Trim())

    Remove-Item Env:AGENT_GUARD_GRAPH_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:AGENT_GUARD_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
} finally {
    Remove-Item -Path $tempTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Guard v4.2 Summary: $passedCount PASSED, $failedCount FAILED" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "=======================================================`n" -ForegroundColor Cyan

if ($failedCount -gt 0) { exit 1 } else { exit 0 }
