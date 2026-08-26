#Requires -Version 5.1
<#
.SYNOPSIS
    Keep the knowledge graph fresh in the background (just watch).

.DESCRIPTION
    Runs `graphify watch . --debounce 3` (AST-only rebuilds on code changes, no
    LLM) as a child process and polls `graphify check-update .` for the
    needs_update flag that code-only rebuilds cannot clear (docs/images/memory).

    Two-tier semantic escalation via GRAPHIFY_SEMANTIC_AUTO:
      unset (default) -> notify only; run `just update-semantic` manually.
      1               -> auto-run `graphify extract .` (headless semantic LLM
                         extraction, uncapped cost mode - deliberate opt-in).

.NOTES
    Launch via `just watch` in a dedicated terminal; Ctrl+C stops both the
    watcher child process and the polling loop.
#>
[CmdletBinding()]
param(
    [int]$PollSeconds = 30
)

$ErrorActionPreference = "Continue"
$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

$semanticAuto = ($env:GRAPHIFY_SEMANTIC_AUTO -eq "1")
$mode = if ($semanticAuto) { "AUTO (graphify extract runs on flag)" } else { "notify-only (set GRAPHIFY_SEMANTIC_AUTO=1 to auto-run)" }
Write-Host "[graph-watch] AST watch starting; semantic escalation: $mode" -ForegroundColor Cyan

$watchProc = Start-Process -FilePath "graphify" -ArgumentList "watch", ".", "--debounce", "3" -NoNewWindow -PassThru

$notified = $false
try {
    while (-not $watchProc.HasExited) {
        Start-Sleep -Seconds $PollSeconds

        $checkOutput = & graphify check-update . 2>&1 | Out-String
        $pending = ($LASTEXITCODE -ne 0) -or ($checkOutput -match "(?i)needs[_ -]?update|pending|stale")
        if (-not $pending) {
            $notified = $false
            continue
        }

        if ($semanticAuto) {
            Write-Host "[graph-watch] needs_update detected -> running semantic extraction (LLM)..." -ForegroundColor Yellow
            & graphify extract .
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[graph-watch] semantic extraction complete." -ForegroundColor Green
            } else {
                Write-Warning "[graph-watch] semantic extraction failed (exit $LASTEXITCODE); will retry on next poll."
            }
        } elseif (-not $notified) {
            Write-Warning "[graph-watch] semantic re-extraction pending (docs/images/memory changed). Run ``just update-semantic`` or set GRAPHIFY_SEMANTIC_AUTO=1."
            $notified = $true
        }
    }
    Write-Warning "[graph-watch] graphify watch exited (code $($watchProc.ExitCode))."
} finally {
    if ($watchProc -and -not $watchProc.HasExited) {
        Stop-Process -Id $watchProc.Id -Force -ErrorAction SilentlyContinue
        Write-Host "[graph-watch] watcher stopped." -ForegroundColor DarkGray
    }
}
