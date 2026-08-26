#Requires -Version 5.1
<#
.SYNOPSIS
    Fail-to-pass tests for agent_guard.py v4.4 (session identity, MCP, thrash, Claude ACI, merge, cumulative read, wait floor).
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
Write-Host "  Agent Guard v4.4 Session / Thrash / Wait / Crawl Regression  " -ForegroundColor Cyan
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
    # Hermetic: never let a real ~/.cache/graphify-queries.log leak graph contact
    # into gate tests (v4.3 default-path fallback). The qlog tests lift this.
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"

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
    # Inside the graph root: absolute paths outside the repo are edit-gate-exempt (v4.3)
    $targetFile = Join-Path $v4Root "edited.txt"
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

    # =====================================================================
    # v4.3: MCP wrapper unwrap / query-log fallback / out-of-repo writes /
    #       batch-end save-result nudge (Cursor field report 2026-08-26)
    # =====================================================================
    $v43Root = Join-Path $tempTestDir "v43_root"
    New-Item -Path (Join-Path $v43Root "graphify-out") -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $v43Root "graphify-out\graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $env:AGENT_GUARD_GRAPH_ROOT = $v43Root
    $env:AGENT_GUARD_LOG = (Join-Path $tempTestDir "v43-log.jsonl")

    # --- v4.3: CallDynamicTool wrapper carrying query_graph records graph contact
    $wrapConv = "v43-wrap-$(Get-Random)"
    $wrapRes = Invoke-GuardHook @{
        toolCall       = @{ name = "CallDynamicTool"; args = @{ namespace = "user-graphify"; toolName = "query_graph"; arguments = @{ question = "how does deploy work" } } }
        conversationId = $wrapConv
    }
    $wrapEdit = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "a.ps1") } }
        conversationId = $wrapConv
    }
    Assert-Test -Name "v4.3 CallDynamicTool(query_graph) is allowed" -Condition ($wrapRes -match '"decision":\s*"allow"') -Details ($wrapRes.Trim())
    Assert-Test -Name "v4.3 wrapper-recorded graph contact allows first edit (no strike)" -Condition ($wrapEdit -match '"decision":\s*"allow"') -Details ($wrapEdit.Trim())

    # --- v4.3: official Cursor beforeMCPExecution schema (docs 2026-08)
    # tool_input is a JSON-params STRING; server is mcp_server_name
    $officialConv = "v43-official-$(Get-Random)"
    $officialRes = Invoke-GuardHook @{
        hook_event_name = "beforeMCPExecution"
        tool_name       = "query_graph"
        tool_input      = '{"question":"deploy","token_budget":1200}'
        mcp_server_name = "user-graphify"
        conversationId  = $officialConv
    }
    $officialEdit = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "official.ps1") } }
        conversationId = $officialConv
    }
    Assert-Test -Name "v4.3 official beforeMCPExecution JSON-string tool_input is allowed" -Condition ($officialRes -match '"decision":\s*"allow"') -Details ($officialRes.Trim())
    Assert-Test -Name "v4.3 official schema records graph contact (no extract_args crash)" -Condition ($officialEdit -match '"decision":\s*"allow"') -Details ($officialEdit.Trim())

    # preToolUse matcher form MCP:<tool_name>
    $colonConv = "v43-colon-$(Get-Random)"
    $colonRes = Invoke-GuardHook @{
        toolCall       = @{ name = "MCP:query_graph"; args = @{ question = "hubs" } }
        conversationId = $colonConv
    }
    $colonEdit = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "colon.ps1") } }
        conversationId = $colonConv
    }
    Assert-Test -Name "v4.3 preToolUse MCP:query_graph records graph contact" -Condition ($colonRes -match '"decision":\s*"allow"' -and $colonEdit -match '"decision":\s*"allow"') -Details ($colonEdit.Trim())

    # --- v4.3: Claude Code mcp__graphify__query_graph PreToolUse records contact
    $ccConv = "v43-claude-mcp-$(Get-Random)"
    $env:CLAUDE_PROJECT_DIR = $v43Root
    $ccMcp = Invoke-GuardProc @{
        hook_event_name = "PreToolUse"
        tool_name       = "mcp__graphify__query_graph"
        tool_input      = @{ question = "deploy"; token_budget = 1200 }
        conversationId  = $ccConv
    }
    $ccEdit = Invoke-GuardProc @{
        hook_event_name = "PreToolUse"
        tool_name       = "Edit"
        tool_input      = @{ path = (Join-Path $v43Root "claude.ps1") }
        conversationId  = $ccConv
    }
    Assert-Test -Name "v4.3 Claude mcp__graphify__query_graph PreToolUse is allowed" -Condition ($ccMcp.stdout -match '"permissionDecision":\s*"allow"' -and [int]$ccMcp.code -eq 0) -Details ($ccMcp.stdout)
    Assert-Test -Name "v4.3 Claude MCP contact allows first Edit (no strike)" -Condition ($ccEdit.stdout -match '"permissionDecision":\s*"allow"' -and [int]$ccEdit.code -eq 0) -Details ($ccEdit.stdout)
    Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue

    # --- v4.3: Antigravity call_mcp_tool PascalCase ToolName/ServerName
    $agyConv = "v43-agy-mcp-$(Get-Random)"
    $agyMcp = Invoke-GuardHook @{
        toolCall       = @{ name = "call_mcp_tool"; args = @{ ServerName = "graphify"; ToolName = "query_graph"; Arguments = @{ question = "deploy" } } }
        conversationId = $agyConv
    }
    $agyEdit = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "agy.ps1") } }
        conversationId = $agyConv
    }
    Assert-Test -Name "v4.3 Antigravity call_mcp_tool(ToolName=query_graph) is allowed" -Condition ($agyMcp -match '"decision":\s*"allow"') -Details ($agyMcp.Trim())
    Assert-Test -Name "v4.3 Antigravity PascalCase unwrap records graph contact" -Condition ($agyEdit -match '"decision":\s*"allow"') -Details ($agyEdit.Trim())

    # --- v4.3: fresh query-log record (corpus inside repo) counts as graph contact
    $qlogFile = Join-Path $tempTestDir "graphify-queries.log"
    $qlogCorpus = (Join-Path $v43Root "graphify-out\graph.json").Replace('\', '\\')
    $qlogTs = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss+00:00")
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$qlogCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    Remove-Item Env:GRAPHIFY_QUERY_LOG_DISABLE -ErrorAction SilentlyContinue
    $env:GRAPHIFY_QUERY_LOG = $qlogFile
    $qlogConv = "v43-qlog-$(Get-Random)"
    $qlogSearch = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } }
        conversationId = $qlogConv
    }
    Assert-Test -Name "v4.3 query-log fallback: unanchored rg allowed on FIRST attempt" -Condition ($qlogSearch -match '"decision":\s*"allow"') -Details ($qlogSearch.Trim())

    # stale/foreign corpus must NOT count as contact
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"C:\\other\\repo\\graphify-out\\graph.json`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv2 = "v43-qlog2-$(Get-Random)"
    $qlogDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } }
        conversationId = $qlogConv2
    }
    Assert-Test -Name "v4.3 query-log fallback: foreign-corpus record still denies" -Condition ($qlogDeny -match '"decision":\s*"deny"') -Details ($qlogDeny.Trim())

    # sibling-prefix corpus (repo-evil) must NOT count as contact (boundary check)
    $siblingCorpus = ($v43Root + "-evil\graphify-out\graph.json").Replace('\', '\\')
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$siblingCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv3 = "v43-qlog3-$(Get-Random)"
    $siblingDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } }
        conversationId = $qlogConv3
    }
    Assert-Test -Name "v4.3 query-log fallback: sibling-prefix corpus (repo-evil) still denies" -Condition ($siblingDeny -match '"decision":\s*"deny"') -Details ($siblingDeny.Trim())

    # home-relative corpus (Cursor global MCP cwd) must NOT count as contact
    $homeCorpus = (Join-Path $env:USERPROFILE "graphify-out\graph.json").Replace('\', '\\')
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$homeCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConvHome = "v43-qlog-home-$(Get-Random)"
    $homeDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } }
        conversationId = $qlogConvHome
    }
    Assert-Test -Name "v4.3 query-log fallback: home-relative corpus still denies" -Condition ($homeDeny -match '"decision":\s*"deny"') -Details ($homeDeny.Trim())

    # unparseable ts must NOT be accepted even when the file mtime is fresh
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"not-a-timestamp`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$qlogCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv4 = "v43-qlog4-$(Get-Random)"
    $badTsDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } }
        conversationId = $qlogConv4
    }
    Assert-Test -Name "v4.3 query-log fallback: unparseable ts still denies (no mtime shortcut)" -Condition ($badTsDeny -match '"decision":\s*"deny"') -Details ($badTsDeny.Trim())

    # future-dated ts (forged record) must NOT count as contact
    $futureTs = (Get-Date).ToUniversalTime().AddHours(2).ToString("yyyy-MM-ddTHH:mm:ss+00:00")
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$futureTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$qlogCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv5 = "v43-qlog5-$(Get-Random)"
    $futureDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo scripts/" } }
        conversationId = $qlogConv5
    }
    Assert-Test -Name "v4.3 query-log fallback: future-dated ts still denies" -Condition ($futureDeny -match '"decision":\s*"deny"') -Details ($futureDeny.Trim())
    Remove-Item Env:GRAPHIFY_QUERY_LOG -ErrorAction SilentlyContinue
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"

    # --- v4.3: out-of-repo write (plan file) skips edit gate and batch-end contract
    $planConv = "v43-plan-$(Get-Random)"
    $planTarget = Join-Path $tempTestDir "outside_repo\test.plan.md"
    $planWrite = Invoke-GuardHook @{
        toolCall       = @{ name = "write_to_file"; args = @{ TargetFile = $planTarget } }
        conversationId = $planConv
    }
    $planStop = Invoke-GuardHook @{
        hook_event_name = "stop"
        conversationId  = $planConv
    }
    Assert-Test -Name "v4.3 out-of-repo write allowed without graph contact (no edit-gate strike)" -Condition ($planWrite -match '"decision":\s*"allow"') -Details ($planWrite.Trim())
    Assert-Test -Name "v4.3 out-of-repo write does not trigger batch-end warning on stop" -Condition ($planStop -notmatch 'Batch End') -Details ($planStop.Trim())

    # --- v4.3: batch-end nudges save-result when graph queries ran but none saved
    $srConv = "v43-sr-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just hubs" } }
        conversationId = $srConv
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "b.ps1") } }
        conversationId = $srConv
    }
    $srStop = Invoke-GuardHook @{
        hook_event_name = "stop"
        conversationId  = $srConv
    }
    Assert-Test -Name "v4.3 batch-end includes save-result nudge (just remember)" -Condition ($srStop -match 'just remember') -Details ($srStop.Trim())

    # after `just remember` ran, the nudge disappears (new conv, save-result recorded)
    $srConv2 = "v43-sr2-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just hubs" } }
        conversationId = $srConv2
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "c.ps1") } }
        conversationId = $srConv2
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = 'just remember "q" "a"' } }
        conversationId = $srConv2
    }
    $srStop2 = Invoke-GuardHook @{
        hook_event_name = "stop"
        conversationId  = $srConv2
    }
    Assert-Test -Name "v4.3 batch-end omits nudge after just remember ran" -Condition ($srStop2 -notmatch 'just remember') -Details ($srStop2.Trim())

    # --- v4.4: cumulative sliced-line cap (closes the N-slice bypass of the 300-line cap)
    $v44Root = Join-Path $tempTestDir "v44_root"
    $v44Graph = Join-Path $v44Root "graphify-out"
    New-Item -Path $v44Graph -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $v44Graph "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $v44Log = Join-Path $tempTestDir "v44-session-log.jsonl"
    $env:AGENT_GUARD_GRAPH_ROOT = $v44Root
    $env:AGENT_GUARD_LOG = $v44Log
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"
    Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue

    $crawlFile = Join-Path $v44Root "crawl.ps1"
    [System.IO.File]::WriteAllText($crawlFile, (("x`n" * 400)), [System.Text.Encoding]::UTF8)
    $crawlConv = "v44-crawl-$(Get-Random)"
    $slice200 = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 1; EndLine = 200 } }
        conversationId = $crawlConv
    }
    Assert-Test -Name "v4.4 first 200-line slice is allowed" -Condition ($slice200 -match '"decision":\s*"allow"') -Details ($slice200.Trim())
    $slice200b = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 201; EndLine = 400 } }
        conversationId = $crawlConv
    }
    Assert-Test -Name "v4.4 second 200-line slice is denied (cumulative > 300)" -Condition ($slice200b -match '"decision":\s*"deny"' -and $slice200b -match 'rtk read' -and $slice200b -match '\^function') -Details ($slice200b.Trim())
    $slice200retry = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 201; EndLine = 400 } }
        conversationId = $crawlConv
    }
    Assert-Test -Name "v4.4 cumulative-cap retry passes (one-strike)" -Condition ($slice200retry -match '"decision":\s*"allow"') -Details ($slice200retry.Trim())

    $pinConv = "v44-pin-$(Get-Random)"
    $pin1 = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 1; EndLine = 20 } }
        conversationId = $pinConv
    }
    $pin2 = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 80; EndLine = 99 } }
        conversationId = $pinConv
    }
    Assert-Test -Name "v4.4 two 20-line pinpoint slices stay allowed" -Condition ($pin1 -match '"decision":\s*"allow"' -and $pin2 -match '"decision":\s*"allow"') -Details (($pin1 + $pin2).Trim())

    $tinyFile = Join-Path $v44Root "tiny.ps1"
    [System.IO.File]::WriteAllText($tinyFile, (("x`n" * 40)), [System.Text.Encoding]::UTF8)
    $tinyConv = "v44-tiny-$(Get-Random)"
    $tiny1 = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $tinyFile; StartLine = 1; EndLine = 200 } }
        conversationId = $tinyConv
    }
    $tiny2 = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $tinyFile; StartLine = 201; EndLine = 400 } }
        conversationId = $tinyConv
    }
    Assert-Test -Name "v4.4 oversized ranges on a 40-line file do not trip the cap (clamped)" -Condition ($tiny1 -match '"decision":\s*"allow"' -and $tiny2 -match '"decision":\s*"allow"') -Details (($tiny1 + $tiny2).Trim())

    $noAccLog = Join-Path $tempTestDir "v44-noacc.jsonl"
    $env:AGENT_GUARD_LOG = $noAccLog
    $noAccConv = "v44-noacc-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 1; EndLine = 200 } }
        conversationId = $noAccConv
    }
    $noAccDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "view_file"; args = @{ path = $crawlFile; StartLine = 201; EndLine = 400 } }
        conversationId = $noAccConv
    }
    $noAccLogText = if (Test-Path $noAccLog) { Get-Content -Raw -Path $noAccLog } else { "" }
    Assert-Test -Name "v4.4 denied slice is not accumulated (read_lines_max stays 200)" -Condition ($noAccDeny -match '"decision":\s*"deny"' -and $noAccLogText -match '"read_lines_max":\s*200' -and $noAccLogText -notmatch '"read_lines_max":\s*400') -Details ($noAccDeny.Trim() + $noAccLogText)
    $env:AGENT_GUARD_LOG = $v44Log

    $curConv = "v44-cursor-limit-$(Get-Random)"
    $cur1 = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        tool_input      = @{ path = $crawlFile; offset = 1; limit = 200 }
        conversationId  = $curConv
    }
    $cur2 = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        tool_input      = @{ path = $crawlFile; offset = 201; limit = 200 }
        conversationId  = $curConv
    }
    Assert-Test -Name "v4.4 Cursor offset/limit 200+200 denies on second slice" -Condition ($cur1 -match '"decision":\s*"allow"' -and $cur2 -match '"decision":\s*"deny"') -Details (($cur1 + $cur2).Trim())

    $mergeConv = "v44-cursor-merge-$(Get-Random)"
    $mergeRead = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        toolCall        = @{ name = "Read"; args = @{ path = $crawlFile } }
        tool_input      = @{ path = $crawlFile; offset = 1; limit = 80 }
        conversationId  = $mergeConv
    }
    Assert-Test -Name "v4.4 Cursor path-only args + tool_input offset/limit is sliced" -Condition ($mergeRead -match '"decision":\s*"allow"') -Details ($mergeRead.Trim())

    $jsonConv = "v44-cursor-jsoninput-$(Get-Random)"
    $jsonInput = (@{ path = $crawlFile; offset = 1; limit = 80 } | ConvertTo-Json -Compress)
    $jsonRead = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        tool_input      = $jsonInput
        conversationId  = $jsonConv
    }
    Assert-Test -Name "v4.4 Cursor JSON-string tool_input offset/limit is sliced" -Condition ($jsonRead -match '"decision":\s*"allow"') -Details ($jsonRead.Trim())

    $keysConv = "v44-unsliced-keys-$(Get-Random)"
    $keysLog = Join-Path $tempTestDir "v44-unsliced-keys.jsonl"
    $env:AGENT_GUARD_LOG = $keysLog
    $keysDeny = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        tool_input      = @{ path = $crawlFile }
        conversationId  = $keysConv
    }
    $keysText = if (Test-Path $keysLog) { Get-Content -Raw -Path $keysLog } else { "" }
    Assert-Test -Name "v4.4 unsliced Cursor Read deny logs arg_keys" -Condition ($keysDeny -match '"decision":\s*"deny"' -and $keysText -match '"arg_keys"') -Details ($keysDeny.Trim() + $keysText)
    $env:AGENT_GUARD_LOG = $v44Log

    $crawlLog = if (Test-Path $v44Log) { Get-Content -Raw -Path $v44Log } else { "" }
    Assert-Test -Name "v4.4 session-log records crawl=true" -Condition ($crawlLog -match '"crawl":\s*true') -Details $v44Log

    # --- v4.4: finite-batch wait floor (explicit short wait / background only)
    $wfCursor = Invoke-GuardHook @{
        tool_name       = "Shell"
        cursor_version  = "1.0"
        tool_input      = @{ command = "just audit"; block_until_ms = 0 }
        conversationId  = "v44-wf-cursor-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 just audit + block_until_ms=0 is denied with 120000" -Condition ($wfCursor -match '"decision":\s*"deny"' -and $wfCursor -match '120000') -Details ($wfCursor.Trim())

    $wfClaude = Invoke-GuardHook @{
        toolCall       = @{ name = "Bash"; args = @{ command = "just audit"; run_in_background = $true } }
        conversationId = "v44-wf-claude-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 just audit + run_in_background is denied" -Condition ($wfClaude -match '"decision":\s*"deny"' -and $wfClaude -match 'run_in_background') -Details ($wfClaude.Trim())

    $wfAgy = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit"; WaitMsBeforeAsync = 5000 } }
        conversationId = "v44-wf-agy-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 just audit + WaitMsBeforeAsync=5000 is denied with 120000" -Condition ($wfAgy -match '"decision":\s*"deny"' -and $wfAgy -match 'WaitMsBeforeAsync=120000') -Details ($wfAgy.Trim())

    $wfAgyConv = "v44-wf-agy-retry-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit"; WaitMsBeforeAsync = 5000 } }
        conversationId = $wfAgyConv
    }
    $wfAgyRetry = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit"; WaitMsBeforeAsync = 5000 } }
        conversationId = $wfAgyConv
    }
    Assert-Test -Name "v4.4 wait-floor retry passes (one-strike)" -Condition ($wfAgyRetry -match '"decision":\s*"allow"') -Details ($wfAgyRetry.Trim())

    $wfDev = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "npm run dev"; WaitMsBeforeAsync = 0; RunPersistent = $true } }
        conversationId = "v44-wf-dev-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 npm run dev background is allowed (watcher exclusion)" -Condition ($wfDev -match '"decision":\s*"allow"') -Details ($wfDev.Trim())

    $wfBare = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit" } }
        conversationId = "v44-wf-bare-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 just audit without wait flags is allowed" -Condition ($wfBare -match '"decision":\s*"allow"') -Details ($wfBare.Trim())

    # --- v4.4: short-wait polling is allow + guidance, never deny
    $pollConv = "v44-poll-$(Get-Random)"
    $poll1 = Invoke-GuardHook @{
        tool_name       = "AwaitShell"
        cursor_version  = "1.0"
        tool_input      = @{ block_until_ms = 5000 }
        conversationId  = $pollConv
    }
    $poll2 = Invoke-GuardHook @{
        tool_name       = "AwaitShell"
        cursor_version  = "1.0"
        tool_input      = @{ block_until_ms = 5000 }
        conversationId  = $pollConv
    }
    $poll3 = Invoke-GuardHook @{
        tool_name       = "AwaitShell"
        cursor_version  = "1.0"
        tool_input      = @{ block_until_ms = 5000 }
        conversationId  = $pollConv
    }
    Assert-Test -Name "v4.4 AwaitShell short-wait streak is allowed (never denied)" -Condition ($poll1 -match '"decision":\s*"allow"' -and $poll2 -match '"decision":\s*"allow"' -and $poll3 -match '"decision":\s*"allow"') -Details (($poll1 + $poll2 + $poll3).Trim())
    Assert-Test -Name "v4.4 AwaitShell 2nd+ short wait emits poll guidance" -Condition ($poll2 -match '\[Wait\]' -and $poll3 -match '\[Wait\]') -Details ($poll2.Trim())
    $pollLog = if (Test-Path $v44Log) { Get-Content -Raw -Path $v44Log } else { "" }
    Assert-Test -Name "v4.4 session-log records poll_guide=true" -Condition ($pollLog -match '"poll_guide":\s*true') -Details $v44Log

    $killPoll = Invoke-GuardHook @{
        toolCall       = @{ name = "manage_task"; args = @{ Action = "kill"; TaskId = "t1" } }
        conversationId = "v44-kill-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 manage_task kill is allowed without poll guidance" -Condition ($killPoll -match '"decision":\s*"allow"' -and $killPoll -notmatch '\[Wait\]') -Details ($killPoll.Trim())

    Remove-Item Env:AGENT_GUARD_GRAPH_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:AGENT_GUARD_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:GRAPHIFY_QUERY_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:GRAPHIFY_QUERY_LOG_DISABLE -ErrorAction SilentlyContinue
} finally {
    Remove-Item -Path $tempTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Guard v4.4 Summary: $passedCount PASSED, $failedCount FAILED" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "=======================================================`n" -ForegroundColor Cyan

if ($failedCount -gt 0) { exit 1 } else { exit 0 }
