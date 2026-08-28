#Requires -Version 5.1
<#
.SYNOPSIS
    Fail-to-pass tests for agent_guard.py v5 (sessionStart context, rtk rewrite, hard-loop stop, Cursor wait floor, graph-gate, read cap, query-log, workspacePaths).
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
Write-Host "  Agent Guard v5 Session / Rewrite / Hard-loop / Wait / Crawl / Shell Regression  " -ForegroundColor Cyan
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
    function Invoke-GuardHookDestructive {
        param([hashtable]$Payload)
        $json = $Payload | ConvertTo-Json -Compress -Depth 8
        [System.IO.File]::WriteAllText($testJsonFile, $json, [System.Text.Encoding]::UTF8)
        return (python -c "import subprocess; p = subprocess.run(['python', '$guardPyEsc', '--mode=destructive'], input=open('$testJsonEsc', 'rb').read(), capture_output=True); print(p.stdout.decode('utf-8'))" 2>&1 | Out-String)
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
    $env:AGENT_GUARD_TEST = "1"

    # --- P0: fallback conv_id is stable without conversationId (ppid must not be used)
    $fbRoot = Join-Path $tempTestDir "fallback_root"
    $fbGraph = Join-Path $fbRoot "graphify-out"
    New-Item -Path $fbGraph -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fbGraph "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $env:AGENT_GUARD_GRAPH_ROOT = $fbRoot
    $env:AGENT_GUARD_LOG = (Join-Path $tempTestDir "fallback-log.jsonl")

    $rgNoId = @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } } }
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

    # --- v4.2: Cursor deny JSON (permission + decision)
    $cursorDenyConv = "test_cursor_deny_$(Get-Random)"
    $cursorDeny = Invoke-GuardProc @{
        tool_name      = "Shell"
        tool_input     = @{ command = "rm -rf /" }
        conversationId = $cursorDenyConv
        hook_event_name = "PreToolUse"
    }
    Assert-Test -Name "v5 Cursor deny: permission deny on destructive" -Condition ($cursorDeny.stdout -match '"permission":\s*"deny"') -Details ($cursorDeny.stdout)
    Assert-Test -Name "v5 Cursor deny: exit 0 (fail-open process, JSON deny)" -Condition ([int]$cursorDeny.code -eq 0) -Details ("exit=" + $cursorDeny.code)
    Assert-Test -Name "v5 Cursor deny: top-level decision deny" -Condition ($cursorDeny.stdout -match '"decision":\s*"deny"') -Details ($cursorDeny.stdout)

    $cursorAllowConv = "test_cursor_allow_$(Get-Random)"
    $cursorAllow = Invoke-GuardProc @{
        tool_name       = "Shell"
        tool_input      = @{ command = "just audit" }
        conversationId  = $cursorAllowConv
        hook_event_name = "PreToolUse"
    }
    Assert-Test -Name "v5 Cursor allow: exit 0" -Condition ([int]$cursorAllow.code -eq 0) -Details ("exit=" + $cursorAllow.code + " out=" + $cursorAllow.stdout)
    Assert-Test -Name "v5 Cursor allow: permission allow" -Condition ($cursorAllow.stdout -match '"permission":\s*"allow"') -Details ($cursorAllow.stdout)

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
    $stateFile = Join-Path $env:TEMP ("cursor_agent_guard\session_" + $mergeConv + ".json")
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
prev = Path(os.environ['TEMP']) / 'cursor_agent_guard' / ('session_win%d_%s.json' % (window - 1, digest))
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
    $winCarry = Invoke-GuardHook @{ toolCall = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } } }
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

    # --- v4.3: mcp__graphify__query_graph PreToolUse records contact
    $mcpConv = "v43-cursor-mcp-$(Get-Random)"
    $ccMcp = Invoke-GuardProc @{
        hook_event_name = "PreToolUse"
        tool_name       = "mcp__graphify__query_graph"
        tool_input      = @{ question = "deploy"; token_budget = 1200 }
        conversationId  = $mcpConv
    }
    $ccEdit = Invoke-GuardProc @{
        hook_event_name = "PreToolUse"
        tool_name       = "Edit"
        tool_input      = @{ path = (Join-Path $v43Root "dummy.ps1") }
        conversationId  = $mcpConv
    }
    Assert-Test -Name "v4.3 mcp__graphify__query_graph PreToolUse is allowed" -Condition (($ccMcp.stdout -match '"permission":\s*"allow"' -or $ccMcp.stdout -match '"decision":\s*"allow"') -and [int]$ccMcp.code -eq 0) -Details ($ccMcp.stdout)
    Assert-Test -Name "v4.3 MCP contact allows first Edit (no strike)" -Condition (($ccEdit.stdout -match '"permission":\s*"allow"' -or $ccEdit.stdout -match '"decision":\s*"allow"') -and [int]$ccEdit.code -eq 0) -Details ($ccEdit.stdout)

    # --- v4.3: CallDynamicTool unwrap records graph contact

    # --- v4.3: fresh query-log record (corpus inside repo) counts as graph contact
    $qlogFile = Join-Path $tempTestDir "graphify-queries.log"
    $qlogCorpus = (Join-Path $v43Root "graphify-out\graph.json").Replace('\', '\\')
    $qlogTs = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss+00:00")
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$qlogCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    Remove-Item Env:GRAPHIFY_QUERY_LOG_DISABLE -ErrorAction SilentlyContinue
    $env:GRAPHIFY_QUERY_LOG = $qlogFile
    $qlogConv = "v43-qlog-$(Get-Random)"
    $qlogSearch = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $qlogConv
    }
    Assert-Test -Name "v4.3 query-log fallback: unanchored rg allowed on FIRST attempt" -Condition ($qlogSearch -match '"decision":\s*"allow"') -Details ($qlogSearch.Trim())

    # stale/foreign corpus must NOT count as contact
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"C:\\other\\repo\\graphify-out\\graph.json`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv2 = "v43-qlog2-$(Get-Random)"
    $qlogDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $qlogConv2
    }
    Assert-Test -Name "v4.3 query-log fallback: foreign-corpus record still denies" -Condition ($qlogDeny -match '"decision":\s*"deny"') -Details ($qlogDeny.Trim())

    # sibling-prefix corpus (repo-evil) must NOT count as contact (boundary check)
    $siblingCorpus = ($v43Root + "-evil\graphify-out\graph.json").Replace('\', '\\')
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$siblingCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv3 = "v43-qlog3-$(Get-Random)"
    $siblingDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $qlogConv3
    }
    Assert-Test -Name "v4.3 query-log fallback: sibling-prefix corpus (repo-evil) still denies" -Condition ($siblingDeny -match '"decision":\s*"deny"') -Details ($siblingDeny.Trim())

    # home-relative corpus (Cursor global MCP cwd) must NOT count as contact
    $homeCorpus = (Join-Path $env:USERPROFILE "graphify-out\graph.json").Replace('\', '\\')
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$qlogTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$homeCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConvHome = "v43-qlog-home-$(Get-Random)"
    $homeDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $qlogConvHome
    }
    Assert-Test -Name "v4.3 query-log fallback: home-relative corpus still denies" -Condition ($homeDeny -match '"decision":\s*"deny"') -Details ($homeDeny.Trim())

    # unparseable ts must NOT be accepted even when the file mtime is fresh
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"not-a-timestamp`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$qlogCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv4 = "v43-qlog4-$(Get-Random)"
    $badTsDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $qlogConv4
    }
    Assert-Test -Name "v4.3 query-log fallback: unparseable ts still denies (no mtime shortcut)" -Condition ($badTsDeny -match '"decision":\s*"deny"') -Details ($badTsDeny.Trim())

    # future-dated ts (forged record) must NOT count as contact
    $futureTs = (Get-Date).ToUniversalTime().AddHours(2).ToString("yyyy-MM-ddTHH:mm:ss+00:00")
    [System.IO.File]::WriteAllText($qlogFile, "{`"ts`": `"$futureTs`", `"kind`": `"mcp_query`", `"question`": `"probe`", `"corpus`": `"$qlogCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    $qlogConv5 = "v43-qlog5-$(Get-Random)"
    $futureDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
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

    # --- semantic batch-end: docs/images require graphify-builder merge
    $semConv = "v43-sem-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just hubs" } }
        conversationId = $semConv
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "doc.md") } }
        conversationId = $semConv
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just update-graph" } }
        conversationId = $semConv
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit" } }
        conversationId = $semConv
    }
    $semStop = Invoke-GuardHook @{
        hook_event_name = "stop"
        conversationId  = $semConv
    }
    Assert-Test -Name "v4.4 batch-end warns when docs edited without semantic-merge" -Condition ($semStop -match 'graphify-builder' -and $semStop -match 'semantic-merge') -Details ($semStop.Trim())

    $semConv2 = "v43-sem2-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just hubs" } }
        conversationId = $semConv2
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root "doc2.md") } }
        conversationId = $semConv2
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just update-graph" } }
        conversationId = $semConv2
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit" } }
        conversationId = $semConv2
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just semantic-merge" } }
        conversationId = $semConv2
    }
    $semStop2 = Invoke-GuardHook @{
        hook_event_name = "stop"
        conversationId  = $semConv2
    }
    Assert-Test -Name "v4.4 batch-end omits semantic warn after just semantic-merge" -Condition ($semStop2 -notmatch 'graphify-builder') -Details ($semStop2.Trim())

# --- Cross-harness leftover: Cursor sessionEnd only
    function Invoke-SemanticPendingSession {
        param([string]$Conv, [string]$DocName)
        $null = Invoke-GuardHook @{
            toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just hubs" } }
            conversationId = $Conv
        }
        $null = Invoke-GuardHook @{
            toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = (Join-Path $v43Root $DocName) } }
            conversationId = $Conv
        }
        $null = Invoke-GuardHook @{
            toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just update-graph" } }
            conversationId = $Conv
        }
        $null = Invoke-GuardHook @{
            toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit" } }
            conversationId = $Conv
        }
    }

    $curConv = "v44-sem-cursor-$(Get-Random)"
    Invoke-SemanticPendingSession -Conv $curConv -DocName "cursor.md"
    $curStop = Invoke-GuardHook @{
        hook_event_name = "sessionEnd"
        cursor_version  = "1.0"
        conversationId  = $curConv
    }
    Assert-Test -Name "Cursor sessionEnd warns graphify-builder after docs edit" -Condition (
        $curStop -match 'graphify-builder' -and $curStop -match 'semantic-merge'
    ) -Details ($curStop.Trim())


    # --- v4.4: cumulative sliced-line cap (closes the N-slice bypass of the 300-line cap)
    $v44Root = Join-Path $tempTestDir "v44_root"
    $v44Graph = Join-Path $v44Root "graphify-out"
    New-Item -Path $v44Graph -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $v44Graph "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $v44Log = Join-Path $tempTestDir "v44-session-log.jsonl"
    $env:AGENT_GUARD_GRAPH_ROOT = $v44Root
    $env:AGENT_GUARD_LOG = $v44Log
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"

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

    $wfCursor5k = Invoke-GuardHook @{
        tool_name       = "Shell"
        cursor_version  = "1.0"
        tool_input      = @{ command = "just audit"; block_until_ms = 5000 }
        conversationId  = "v5-wf-cursor-5k-$(Get-Random)"
    }
    Assert-Test -Name "v5 just audit + block_until_ms=5000 is denied with 120000" -Condition ($wfCursor5k -match '"decision":\s*"deny"' -and $wfCursor5k -match '120000') -Details ($wfCursor5k.Trim())

    $wfBg = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "just audit"; run_in_background = $true } }
        conversationId = "v44-wf-bg-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 just audit + run_in_background is denied" -Condition ($wfBg -match '"decision":\s*"deny"' -and $wfBg -match 'run_in_background') -Details ($wfBg.Trim())

    $wfWait = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "just audit"; block_until_ms = 5000 } }
        conversationId = "v44-wf-wait-$(Get-Random)"
    }
    Assert-Test -Name "v4.4 just audit + block_until_ms=5000 is denied with 120000" -Condition ($wfWait -match '"decision":\s*"deny"' -and $wfWait -match 'block_until_ms=120000') -Details ($wfWait.Trim())

    $wfWaitConv = "v44-wf-wait-retry-$(Get-Random)"
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "just audit"; block_until_ms = 5000 } }
        conversationId = $wfWaitConv
    }
    $wfWaitRetry = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "just audit"; block_until_ms = 5000 } }
        conversationId = $wfWaitConv
    }
    Assert-Test -Name "v4.4 wait-floor retry passes (one-strike)" -Condition ($wfWaitRetry -match '"decision":\s*"allow"') -Details ($wfWaitRetry.Trim())

    $wfDev = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "npm run dev"; run_in_background = $true } }
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

    # =====================================================================
    # v4.5: Cursor offset=1 whole-file, query-log 180s window,
    #       beforeMCP session-log dedup (Cursor session 5ca2d438)
    # v4.6: pwsh host — && is legal; deny only explicit powershell.exe + &&
    # =====================================================================
    $env:AGENT_GUARD_GRAPH_ROOT = $v44Root
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"
    $v45Log = Join-Path $tempTestDir "v45-session-log.jsonl"
    $env:AGENT_GUARD_LOG = $v45Log

    $psAndConv = "v46-psand-$(Get-Random)"
    $psAndAllow = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "echo a && echo b" } }
        conversationId = $psAndConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 Cursor Shell echo && echo is allowed (pwsh host)" -Condition ($psAndAllow -match '"decision":\s*"allow"') -Details ($psAndAllow.Trim())

    $psSemiConv = "v46-pssemi-$(Get-Random)"
    $psSemi = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "echo a; echo b" } }
        conversationId = $psSemiConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 Cursor Shell echo ; echo is allowed" -Condition ($psSemi -match '"decision":\s*"allow"') -Details ($psSemi.Trim())

    $psCmdConv = "v46-pscmd-$(Get-Random)"
    $psCmdAllow = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "cmd /c echo a && echo b" } }
        conversationId = $psCmdConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 unquoted cmd /c echo && echo is allowed (pwsh parses && first)" -Condition ($psCmdAllow -match '"decision":\s*"allow"') -Details ($psCmdAllow.Trim())

    $psCmdQConv = "v46-pscmdq-$(Get-Random)"
    $psCmdQ = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "cmd /c `"echo a && echo b`"" } }
        conversationId = $psCmdQConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 quoted cmd /c `"echo && echo`" is allowed" -Condition ($psCmdQ -match '"decision":\s*"allow"') -Details ($psCmdQ.Trim())

    $psQuotedConv = "v46-psquoted-$(Get-Random)"
    $psQuoted = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "rtk git log --format=`"%h && %s`"" } }
        conversationId = $psQuotedConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 quoted && inside git format is not a chain deny" -Condition ($psQuoted -match '"decision":\s*"allow"') -Details ($psQuoted.Trim())

    $winpsConv = "v46-winps-$(Get-Random)"
    $winpsDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "powershell.exe echo a && echo b" } }
        conversationId = $winpsConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 explicit powershell.exe echo && echo is denied" -Condition ($winpsDeny -match '"decision":\s*"deny"' -and $winpsDeny -match 'Shell Stability' -and $winpsDeny -match 'pwsh') -Details ($winpsDeny.Trim())

    $winpsCmdConv = "v46-winpscmd-$(Get-Random)"
    $winpsCmdDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "powershell.exe -Command `"echo a && echo b`"" } }
        conversationId = $winpsCmdConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 powershell.exe -Command `"echo && echo`" is denied" -Condition ($winpsCmdDeny -match '"decision":\s*"deny"' -and $winpsCmdDeny -match 'Shell Stability') -Details ($winpsCmdDeny.Trim())

    $pwshCmdConv = "v46-pwshcmd-$(Get-Random)"
    $pwshCmdAllow = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "pwsh -NoProfile -Command `"echo a && echo b`"" } }
        conversationId = $pwshCmdConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 pwsh -Command `"echo && echo`" is allowed" -Condition ($pwshCmdAllow -match '"decision":\s*"allow"') -Details ($pwshCmdAllow.Trim())

    $wordConv = "v46-psword-$(Get-Random)"
    $wordAllow = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "echo powershell && echo ok" } }
        conversationId = $wordConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 echo powershell && echo is not a 5.1 launcher deny" -Condition ($wordAllow -match '"decision":\s*"allow"') -Details ($wordAllow.Trim())

    $pyMentionConv = "v46-pymention-$(Get-Random)"
    $pyMention = Invoke-GuardHook @{
        toolCall       = @{ name = "Shell"; args = @{ command = "python -c `"print('powershell.exe echo a && echo b')`"" } }
        conversationId = $pyMentionConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v4.6 python -c string mentioning powershell.exe && is allowed" -Condition ($pyMention -match '"decision":\s*"allow"') -Details ($pyMention.Trim())

    $posixAnd = Invoke-GuardProc @{
        tool_name       = "Shell"
        tool_input      = @{ command = "echo a && echo b" }
        conversationId  = "v46-posix-and-$(Get-Random)"
        hook_event_name = "PreToolUse"
    }
    Assert-Test -Name "v4.6 echo && echo is allowed" -Condition (($posixAnd.stdout -match '"permission":\s*"allow"' -or $posixAnd.stdout -match '"decision":\s*"allow"') -and [int]$posixAnd.code -eq 0) -Details ($posixAnd.stdout)

    $off1Conv = "v45-offset1-$(Get-Random)"
    $off1Deny = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        tool_input      = @{ path = $crawlFile; offset = 1 }
        conversationId  = $off1Conv
    }
    Assert-Test -Name "v4.5 Cursor Read offset=1 no limit is unsliced Gate 1" -Condition ($off1Deny -match '"decision":\s*"deny"' -and $off1Deny -match 'exceeds' -and $off1Deny -match 'rtk read' -and $off1Deny -notmatch 'cumulative') -Details ($off1Deny.Trim())

    $off0Conv = "v45-offset0-$(Get-Random)"
    $off0Deny = Invoke-GuardHook @{
        tool_name       = "Read"
        cursor_version  = "1.0"
        tool_input      = @{ path = $crawlFile; offset = 0 }
        conversationId  = $off0Conv
    }
    Assert-Test -Name "v4.5 Cursor Read offset=0 no limit is unsliced Gate 1" -Condition ($off0Deny -match '"decision":\s*"deny"' -and $off0Deny -match 'exceeds' -and $off0Deny -match 'rtk read') -Details ($off0Deny.Trim())

    $staleLog = Join-Path $tempTestDir "v45-stale-queries.log"
    $staleCorpus = (Join-Path $v44Root "graphify-out\graph.json").Replace('\', '\\')
    $staleTs = (Get-Date).ToUniversalTime().AddHours(-3).ToString("yyyy-MM-ddTHH:mm:ss+00:00")
    [System.IO.File]::WriteAllText($staleLog, "{`"ts`": `"$staleTs`", `"kind`": `"mcp_query`", `"question`": `"old`", `"corpus`": `"$staleCorpus`"}`n", [System.Text.UTF8Encoding]::new($false))
    Remove-Item Env:GRAPHIFY_QUERY_LOG_DISABLE -ErrorAction SilentlyContinue
    $env:GRAPHIFY_QUERY_LOG = $staleLog
    $staleConv = "v45-qlog-stale-$(Get-Random)"
    $staleDeny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $staleConv
    }
    Assert-Test -Name "v4.5 query-log fallback: 3h-old record still denies (180s window)" -Condition ($staleDeny -match '"decision":\s*"deny"' -and $staleDeny -match 'Graph-First') -Details ($staleDeny.Trim())
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"
    Remove-Item Env:GRAPHIFY_QUERY_LOG -ErrorAction SilentlyContinue

    $dupLog = Join-Path $tempTestDir "v45-mcp-dup.jsonl"
    $env:AGENT_GUARD_LOG = $dupLog
    $dupConv = "v45-mcp-dup-$(Get-Random)"
    Invoke-GuardHook @{
        toolCall       = @{ name = "CallDynamicTool"; args = @{ namespace = "user-graphify"; toolName = "get_neighbors"; arguments = @{ label = "x" } } }
        conversationId = $dupConv
        cursor_version = "1.0"
    } | Out-Null
    Invoke-GuardHook @{
        hook_event_name = "beforeMCPExecution"
        tool_name       = "get_neighbors"
        tool_input      = '{"label":"x"}'
        mcp_server_name = "user-graphify"
        conversationId  = $dupConv
        cursor_version  = "1.0"
    } | Out-Null
    $dupText = if (Test-Path $dupLog) { Get-Content -Raw -Path $dupLog } else { "" }
    $dupCount = ([regex]::Matches($dupText, '"tool":\s*"get_neighbors"')).Count
    Assert-Test -Name "v4.5 beforeMCPExecution does not duplicate session-log row" -Condition ($dupCount -eq 1) -Details ("count=$dupCount log=$dupText")

    # --- v4.7: Workspace discovery from payload workspacePaths without AGENT_GUARD_GRAPH_ROOT
    Remove-Item Env:AGENT_GUARD_GRAPH_ROOT -ErrorAction SilentlyContinue
    $v47Root = Join-Path $tempTestDir "v47_workspace_root"
    $v47GraphDir = Join-Path $v47Root "graphify-out"
    New-Item -Path $v47GraphDir -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $v47GraphDir "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $v47Conv = "v47-ws-disc-$(Get-Random)"
    $v47Deny = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $v47Conv
        workspacePaths = @($v47Root)
    }
    Assert-Test -Name "v4.7 global hook workspace discovery via workspacePaths triggers graph-gate" -Condition ($v47Deny -match '"decision":\s*"deny"' -and $v47Deny -match 'Graph-First') -Details ($v47Deny.Trim())

    # =====================================================================
    # v5: sessionStart context, rtk rewrite-allow, hard-loop stop
    # =====================================================================
    $v5Root = Join-Path $tempTestDir "v5_root"
    $v5GraphDir = Join-Path $v5Root "graphify-out"
    New-Item -Path $v5GraphDir -ItemType Directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $v5GraphDir "graph.json"), '{"nodes":[],"links":[]}', [System.Text.Encoding]::UTF8)
    $env:AGENT_GUARD_GRAPH_ROOT = $v5Root
    $env:AGENT_GUARD_LOG = (Join-Path $tempTestDir "v5-session-log.jsonl")
    $env:GRAPHIFY_QUERY_LOG_DISABLE = "1"

    $v5SsConv = "v5-ss-$(Get-Random)"
    $v5Ss = Invoke-GuardHook @{
        hook_event_name = "sessionStart"
        cursor_version  = "1.0"
        conversationId  = $v5SsConv
    }
    Assert-Test -Name "v5 sessionStart additional_context mentions graph-first/pins/lessons" -Condition (
        $v5Ss -match 'additional_context' -and (
            $v5Ss -match 'graph-first' -or $v5Ss -match 'pins' -or $v5Ss -match 'lessons'
        )
    ) -Details ($v5Ss.Trim())

    $v5RtkConv = "v5-rtk-$(Get-Random)"
    $v5Rtk = Invoke-GuardHook @{
        tool_name       = "Shell"
        cursor_version  = "1.0"
        tool_input      = @{ command = "git log -n 10 --oneline" }
        conversationId  = $v5RtkConv
    }
    $v5RtkAllow = ($v5Rtk -match '"permission":\s*"allow"' -or $v5Rtk -match '"decision":\s*"allow"')
    Assert-Test -Name "v5 Shell git log is allow with updated_input rtk rewrite (not deny)" -Condition (
        $v5RtkAllow -and $v5Rtk -match 'updated_input' -and $v5Rtk -match 'rtk git'
    ) -Details ($v5Rtk.Trim())

    $v5LoopConv = "v5-loop-$(Get-Random)"
    $v5LoopFile = Join-Path $v5Root "loop.txt"
    [System.IO.File]::WriteAllText($v5LoopFile, "content`n", [System.Text.Encoding]::UTF8)
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $v5LoopFile } }
        conversationId = $v5LoopConv
        cursor_version = "1.0"
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $v5LoopFile } }
        conversationId = $v5LoopConv
        cursor_version = "1.0"
    }
    $v5Stop1 = Invoke-GuardHook @{
        hook_event_name = "stop"
        cursor_version  = "1.0"
        conversationId  = $v5LoopConv
    }
    $v5Stop2 = Invoke-GuardHook @{
        hook_event_name = "stop"
        cursor_version  = "1.0"
        conversationId  = $v5LoopConv
    }
    Assert-Test -Name "v5 hard loop: first stop followup_message + just update-graph" -Condition (
        $v5Stop1 -match 'followup_message' -and $v5Stop1 -match 'just update-graph'
    ) -Details ($v5Stop1.Trim())
    Assert-Test -Name "v5 hard loop: second stop still followup (no one-strike silence)" -Condition (
        $v5Stop2 -match 'followup_message' -and $v5Stop2 -match 'just update-graph'
    ) -Details ($v5Stop2.Trim())

    $v5DoneConv = "v5-done-$(Get-Random)"
    $v5DoneFile = Join-Path $v5Root "done.ps1"
    [System.IO.File]::WriteAllText($v5DoneFile, "Write-Host ok`n", [System.Text.Encoding]::UTF8)
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just hubs" } }
        conversationId = $v5DoneConv
        cursor_version = "1.0"
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $v5DoneFile } }
        conversationId = $v5DoneConv
        cursor_version = "1.0"
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just update-graph" } }
        conversationId = $v5DoneConv
        cursor_version = "1.0"
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just audit" } }
        conversationId = $v5DoneConv
        cursor_version = "1.0"
    }
    $v5DoneStop = Invoke-GuardHook @{
        hook_event_name = "stop"
        cursor_version  = "1.0"
        conversationId  = $v5DoneConv
    }
    Assert-Test -Name "v5 stop does not followup for missing update-graph after update-graph+audit" -Condition (
        $v5DoneStop -notmatch 'just update-graph'
    ) -Details ($v5DoneStop.Trim())

    $v51UgConv = "v51-ug-$(Get-Random)"
    $v51UgFile = Join-Path $v5Root "ug-only.ps1"
    [System.IO.File]::WriteAllText($v51UgFile, "Write-Host ug`n", [System.Text.Encoding]::UTF8)
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $v51UgFile } }
        conversationId = $v51UgConv
        cursor_version = "1.0"
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $v51UgFile } }
        conversationId = $v51UgConv
        cursor_version = "1.0"
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "just update-graph" } }
        conversationId = $v51UgConv
        cursor_version = "1.0"
    }
    $v51UgStop = Invoke-GuardHook @{
        hook_event_name = "stop"
        cursor_version  = "1.0"
        conversationId  = $v51UgConv
    }
    Assert-Test -Name "v5.1 stop does not followup after update-graph without audit" -Condition (
        $v51UgStop -notmatch 'followup_message'
    ) -Details ($v51UgStop.Trim())

    $v51DestConv = "v51-dest-$(Get-Random)"
    $v51DestRg = Invoke-GuardHookDestructive @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rg -n foo" } }
        conversationId = $v51DestConv
        cursor_version = "1.0"
    }
    $v51DestRm = Invoke-GuardHookDestructive @{
        toolCall       = @{ name = "run_command"; args = @{ CommandLine = "rm -rf /" } }
        conversationId = $v51DestConv
        cursor_version = "1.0"
    }
    Assert-Test -Name "v5.1 destructive mode allows unanchored rg" -Condition ($v51DestRg -match '"decision":\s*"allow"') -Details ($v51DestRg.Trim())
    Assert-Test -Name "v5.1 destructive mode still hard-denies wipe" -Condition ($v51DestRm -match '"decision":\s*"deny"') -Details ($v51DestRm.Trim())

    $scopedGrepConv = "v51-scoped-grep-$(Get-Random)"
    $scopedGrep = Invoke-GuardHook @{
        toolCall       = @{ name = "Grep"; args = @{ pattern = "TODO"; path = "scripts" } }
        conversationId = $scopedGrepConv
    }
    Assert-Test -Name "v5.1 Grep with path is allowed before graph contact" -Condition ($scopedGrep -match '"decision":\s*"allow"') -Details ($scopedGrep.Trim())

    Remove-Item Env:AGENT_GUARD_GRAPH_ROOT -ErrorAction SilentlyContinue
    $noGraphRoot = Join-Path $tempTestDir "v51_nograph"
    New-Item -Path $noGraphRoot -ItemType Directory -Force | Out-Null
    $env:AGENT_GUARD_GRAPH_ROOT = $noGraphRoot
    $noGraphEditConv = "v51-nograph-stop-$(Get-Random)"
    $noGraphFile = Join-Path $noGraphRoot "x.ps1"
    [System.IO.File]::WriteAllText($noGraphFile, "ok`n", [System.Text.Encoding]::UTF8)
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $noGraphFile } }
        conversationId = $noGraphEditConv
    }
    $null = Invoke-GuardHook @{
        toolCall       = @{ name = "replace_file_content"; args = @{ TargetFile = $noGraphFile } }
        conversationId = $noGraphEditConv
    }
    $noGraphStop = Invoke-GuardHook @{
        hook_event_name = "stop"
        conversationId  = $noGraphEditConv
    }
    Assert-Test -Name "v5.1 stop does not followup when graph.json is absent" -Condition (
        $noGraphStop -notmatch 'followup_message'
    ) -Details ($noGraphStop.Trim())

    Remove-Item Env:AGENT_GUARD_GRAPH_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:AGENT_GUARD_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:AGENT_GUARD_TEST -ErrorAction SilentlyContinue
    Remove-Item Env:GRAPHIFY_QUERY_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:GRAPHIFY_QUERY_LOG_DISABLE -ErrorAction SilentlyContinue
} finally {
    Remove-Item -Path $tempTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Guard v5 Summary: $passedCount PASSED, $failedCount FAILED" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "=======================================================`n" -ForegroundColor Cyan

if ($failedCount -gt 0) { exit 1 } else { exit 0 }
