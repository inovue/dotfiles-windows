#Requires -Version 5.1
<#
.SYNOPSIS
    Fail-to-pass tests for session-bound semantic graph plumbing (no headless LLM).
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
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkGray }
        $script:failedCount++
    }
}

$justfile = Get-Content (Join-Path $rootDir "justfile") -Raw
Assert-Test -Name "justfile has no update-semantic / graphify extract recipe" -Condition (
    $justfile -notmatch '(?m)^update-semantic:' -and
    $justfile -notmatch 'graphify extract'
) -Details "update-semantic must stay deleted"
Assert-Test -Name "justfile update-graph uses --force then rehydrate --force" -Condition (
    $justfile -match 'graphify update \. --force' -and
    $justfile -match 'graphify_semantic\.py rehydrate --force'
)
Assert-Test -Name "justfile check-semantic also runs prepare" -Condition (
    $justfile -match '(?m)^check-semantic:' -and
    $justfile -match 'graphify_semantic\.py prepare --quiet-if-clean'
)
Assert-Test -Name "justfile session-report prints semantic status" -Condition (
    $justfile -match 'graphify_semantic\.py status'
)
Assert-Test -Name "justfile watch is graphify watch (no graph_watch.ps1)" -Condition (
    $justfile -match 'graphify watch \. --debounce 3' -and
    $justfile -notmatch 'graph_watch\.ps1'
)
Assert-Test -Name "scripts/graph_watch.ps1 is removed" -Condition (
    -not (Test-Path (Join-Path $rootDir "scripts\graph_watch.ps1"))
)
Assert-Test -Name "graphify_semantic.py exists" -Condition (
    Test-Path (Join-Path $rootDir "scripts\graphify_semantic.py")
)

$masterBuilder = Join-Path $rootDir "configs\agents\skills\graphify-builder"
$deployedBuilders = @(
    @{ Name = "Cursor ~/.cursor/skills"; Path = Join-Path $env:USERPROFILE ".cursor\skills\graphify-builder" }
)
$sidecarRel = @(
    "SKILL.md"
    "references\extract.md"
    "references\extraction-spec.md"
)
foreach ($dest in $deployedBuilders) {
    foreach ($rel in $sidecarRel) {
        $src = Join-Path $masterBuilder $rel
        $copy = Join-Path $dest.Path $rel
        $same = $false
        if ((Test-Path $src) -and (Test-Path $copy)) {
            $same = ((Get-FileHash $src -Algorithm SHA256).Hash -eq (Get-FileHash $copy -Algorithm SHA256).Hash)
        }
        Assert-Test -Name ("{0} {1} matches SSOT" -f $dest.Name, $rel) -Condition $same -Details $copy
    }
}

$projectHooks = Get-Content (Join-Path $rootDir ".cursor\hooks.json") -Raw
Assert-Test -Name "Project hooks register sessionStart -> agent_guard" -Condition (
    $projectHooks -match '"sessionStart"' -and $projectHooks -match 'agent_guard\.py'
)
Assert-Test -Name "Project hooks register afterFileEdit -> agent_guard" -Condition (
    $projectHooks -match '"afterFileEdit"' -and $projectHooks -match 'agent_guard\.py'
)
Assert-Test -Name "Project hooks register stop -> agent_guard" -Condition (
    $projectHooks -match '"stop"' -and $projectHooks -match 'agent_guard\.py'
)
Assert-Test -Name "Project hooks register sessionEnd -> agent_guard" -Condition (
    $projectHooks -match '"sessionEnd"' -and $projectHooks -match 'agent_guard\.py'
)
$userHooks = Get-Content (Join-Path $env:USERPROFILE ".cursor\hooks.json") -Raw
Assert-Test -Name "User hooks are destructive Shell-only (no stop/Read)" -Condition (
    $userHooks -match '--mode=destructive' -and $userHooks -match '"Shell"' -and $userHooks -notmatch '"stop"'
)

$freshNeedle = "graphify-builder"
$alwaysOn = @(
    @{ Name = "Cursor User AGENTS.md"; Path = Join-Path $env:APPDATA "Cursor\User\AGENTS.md" }
)
foreach ($rule in $alwaysOn) {
    $text = if (Test-Path $rule.Path) { Get-Content $rule.Path -Raw } else { "" }
    Assert-Test -Name ("{0} always-on rules name graphify-builder" -f $rule.Name) -Condition (
        $text -match [regex]::Escape($freshNeedle) -and $text -match 'semantic-merge'
    ) -Details $rule.Path
}

$fixtureRoot = Join-Path $env:TEMP ("gf-sem-" + [guid]::NewGuid().ToString("n"))
New-Item -Path $fixtureRoot -ItemType Directory -Force | Out-Null
$outDir = Join-Path $fixtureRoot "graphify-out"
New-Item -Path $outDir -ItemType Directory -Force | Out-Null

@'
def hello():
    return 1
'@ | Set-Content -Path (Join-Path $fixtureRoot "hello.py") -Encoding utf8

@'
# Hello
The hello() helper is the public API.
'@ | Set-Content -Path (Join-Path $fixtureRoot "README.md") -Encoding utf8

@'
@AGENTS.md
'@ | Set-Content -Path (Join-Path $fixtureRoot "POINTER.md") -Encoding utf8

New-Item -Path (Join-Path $outDir "memory") -ItemType Directory -Force | Out-Null
@'
# remembered Q
just remember should not be a semantic extract target
'@ | Set-Content -Path (Join-Path $outDir "memory\foo.md") -Encoding utf8

@'
gui:
  nerdFontsVersion: "3"
'@ | Set-Content -Path (Join-Path $fixtureRoot "config.yml") -Encoding utf8

$specDir = Join-Path $fixtureRoot "configs\agents\skills\graphify-builder\references"
New-Item -Path $specDir -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $rootDir "configs\agents\skills\graphify-builder\references\extraction-spec.md") -Destination (Join-Path $specDir "extraction-spec.md")

$scriptPath = Join-Path $rootDir "scripts\graphify_semantic.py"
Push-Location $fixtureRoot
try {
    $prep = & uv tool run --from graphifyy python $scriptPath prepare --root $fixtureRoot 2>&1 | Out-String
    $uncachedList = ""
    $uncachedPath = Join-Path $outDir ".graphify_uncached.txt"
    if (Test-Path $uncachedPath) { $uncachedList = Get-Content $uncachedPath -Raw }
    Assert-Test -Name "prepare writes .graphify_uncached.txt" -Condition (
        Test-Path $uncachedPath
    ) -Details $prep
    Assert-Test -Name "prepare reports pending uncached files" -Condition (
        $prep -match 'uncached' -and $uncachedList -match 'README\.md'
    ) -Details $prep
    Assert-Test -Name "prepare omits pointer, graphify-out memory, and yaml" -Condition (
        $uncachedList -notmatch 'CLAUDE\.md' -and
        $uncachedList -notmatch 'memory[/\\]foo' -and
        $uncachedList -notmatch 'config\.yml'
    ) -Details $uncachedList

    $semantic = @{
        nodes = @(
            @{
                id              = "readme_public_api"
                label           = "public API"
                file_type       = "concept"
                source_file     = "README.md"
                source_location = "L2"
            }
            @{
                id              = "readme_hello_helper"
                label           = "hello helper"
                file_type       = "concept"
                source_file     = "README.md"
                source_location = "L2"
            }
        )
        edges = @(
            @{
                source           = "readme_public_api"
                target           = "readme_hello_helper"
                relation         = "conceptually_related_to"
                confidence       = "INFERRED"
                confidence_score = 0.85
                source_file      = "README.md"
                source_location  = "L2"
                weight           = 1.0
            }
        )
        hyperedges    = @()
        input_tokens  = 0
        output_tokens = 0
    }
    $semPath = Join-Path $outDir ".graphify_semantic.json"
    [System.IO.File]::WriteAllText(
        $semPath,
        ($semantic | ConvertTo-Json -Depth 8 -Compress),
        [System.Text.UTF8Encoding]::new($false)
    )

    $merge = & uv tool run --from graphifyy python $scriptPath merge --root $fixtureRoot --force 2>&1 | Out-String
    $graphPath = Join-Path $outDir "graph.json"

    function Test-HasInferredEdge {
        param([string]$Path)
        if (-not (Test-Path $Path)) { return $false }
        $graph = Get-Content $Path -Raw | ConvertFrom-Json
        $links = @($graph.links)
        if (-not $links -or $links.Count -eq 0) { $links = @($graph.edges) }
        foreach ($e in $links) {
            if ($e.confidence -eq "INFERRED") { return $true }
        }
        return $false
    }

    Assert-Test -Name "merge writes graph.json with an INFERRED edge" -Condition (
        (Test-Path $graphPath) -and (Test-HasInferredEdge $graphPath)
    ) -Details $merge

    $prep2 = & uv tool run --from graphifyy python $scriptPath prepare --root $fixtureRoot 2>&1 | Out-String
    $labelsPath = Join-Path $outDir ".graphify_target_labels.txt"
    Assert-Test -Name "prepare writes .graphify_target_labels.txt" -Condition (
        (Test-Path $labelsPath) -and ((Get-Item $labelsPath).Length -gt 0)
    ) -Details $prep2

    $chunkOnlyRoot = Join-Path $env:TEMP ("gf-sem-chunk-" + [guid]::NewGuid().ToString("n"))
    New-Item -Path $chunkOnlyRoot -ItemType Directory -Force | Out-Null
    $chunkOut = Join-Path $chunkOnlyRoot "graphify-out"
    New-Item -Path $chunkOut -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot "hello.py") -Destination (Join-Path $chunkOnlyRoot "hello.py")
    Copy-Item -Path (Join-Path $fixtureRoot "README.md") -Destination (Join-Path $chunkOnlyRoot "README.md")
    $chunkSpecDir = Join-Path $chunkOnlyRoot "configs\agents\skills\graphify-builder\references"
    New-Item -Path $chunkSpecDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $specDir "extraction-spec.md") -Destination (Join-Path $chunkSpecDir "extraction-spec.md")
    $chunkPayload = @{
        nodes = @(
            @{
                id              = "readme_chunk_api"
                label           = "chunk public API"
                file_type       = "concept"
                source_file     = "README.md"
                source_location = "L2"
            }
        )
        edges = @(
            @{
                source           = "readme_chunk_api"
                target           = "hello"
                relation         = "documents"
                confidence       = "INFERRED"
                confidence_score = 0.85
                source_file      = "README.md"
                source_location  = "L2"
                weight           = 1.0
            }
        )
        hyperedges    = @()
        input_tokens  = 0
        output_tokens = 0
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $chunkOut ".graphify_chunk_01.json"),
        ($chunkPayload | ConvertTo-Json -Depth 8 -Compress),
        [System.Text.UTF8Encoding]::new($false)
    )
    $chunkMerge = & uv tool run --from graphifyy python $scriptPath merge --root $chunkOnlyRoot --force 2>&1 | Out-String
    $chunkGraph = Join-Path $chunkOut "graph.json"
    Assert-Test -Name "merge unions .graphify_chunk_*.json without semantic.json" -Condition (
        (Test-Path $chunkGraph) -and (Test-HasInferredEdge $chunkGraph)
    ) -Details $chunkMerge
    Remove-Item -LiteralPath $chunkOnlyRoot -Recurse -Force -ErrorAction SilentlyContinue

    $forceOut = & graphify update . --force 2>&1 | Out-String
    $forceOk = ($LASTEXITCODE -eq 0)
    $rehydrate = & uv tool run --from graphifyy python $scriptPath rehydrate --root $fixtureRoot 2>&1 | Out-String
    $rehydrateOk = ($LASTEXITCODE -eq 0)
    Assert-Test -Name "update --force then rehydrate keeps INFERRED edges" -Condition (
        $forceOk -and $rehydrateOk -and (Test-HasInferredEdge $graphPath)
    ) -Details ($forceOut + $rehydrate)
} finally {
    Pop-Location
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Semantic harness: $passedCount passed, $failedCount failed"
if ($failedCount -gt 0) { exit 1 }
exit 0
