#Requires -Version 5.1
<#
.SYNOPSIS
    dotfiles-windows 統合ワークスペース監査・クリーンアップスクリプト
.DESCRIPTION
    1. 環境・CLI・安全環境変数・AST・UTF-8 BOM の網羅的検証 (verify_tools.ps1)
       およびセキュリティ回帰 (verify_security.ps1)
    2. AI Agent SSOT ルール＆スキルの同期状態検査 (sync_agent_rules.ps1 -Check)
    3. ナレッジグラフ (graphify-out/graph.json) の健全性・鮮度・孤立率・トポロジーハブ検査
    4. 一時ファイル・バックアップファイル・Git 作業ツリーのクリーン度検査 / クリーンアップ (-Clean)
.PARAMETER Clean
    一時ファイル、古いバックアップ (*.bak)、キャッシュファイルを消去します。
#>
[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = "Continue"

# UTF-8 出力エンコーディング
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = Split-Path -Parent $PSScriptRoot
$testsScript = Join-Path $rootDir "tests\verify_tools.ps1"
$secScript  = Join-Path $rootDir "tests\verify_security.ps1"
$guardTestScript = Join-Path $rootDir "tests\verify_agent_guard.ps1"
$syncScript  = Join-Path $rootDir "scripts\sync_agent_rules.ps1"
$graphJson   = Join-Path $rootDir "graphify-out\graph.json"

$junkPatterns = @("*.bak", "*.backup", "*.tmp", "*.old", "*.orig", "*~", "transcript*.txt")

if ($Clean) {
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    Write-Host "   Workspace Cleanup & Artifact Sanitizer              " -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    $removedCount = 0
    foreach ($pat in $junkPatterns) {
        $matched = Get-ChildItem -Path $rootDir -Filter $pat -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" }
        foreach ($f in $matched) {
            try {
                Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                Write-Host "  [REMOVED] $($f.FullName)" -ForegroundColor Yellow
                $removedCount++
            } catch {
                Write-Warning "  [FAILED] Could not remove $($f.FullName): $_"
            }
        }
    }
    if ($removedCount -eq 0) {
        Write-Host "[OK] Workspace is already completely clean. Zero junk files found." -ForegroundColor Green
    } else {
        Write-Host "[OK] Cleaned $removedCount temporary / backup files." -ForegroundColor Green
    }
    exit 0
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "   AI Agent & Workspace Unified Audit Harness          " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$auditFailed = $false

# --- Phase 1: Environment & Integration Test Suite ---
Write-Host "`n[Audit Phase 1/4] Running Environment Verification Suite..." -ForegroundColor White
$testProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $testsScript -NoNewWindow -Wait -PassThru
if ($testProc.ExitCode -ne 0) {
    Write-Warning "[FAIL] Environment verification tests failed (ExitCode: $($testProc.ExitCode))."
    $auditFailed = $true
} else {
    Write-Host "[PASS] Phase 1a: Environment verification suite passed." -ForegroundColor Green
}

Write-Host "`n[Audit Phase 1b/4] Running Security Regression Suite..." -ForegroundColor White
if (Test-Path $secScript) {
    $secProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $secScript -NoNewWindow -Wait -PassThru
    if ($secProc.ExitCode -ne 0) {
        Write-Warning "[FAIL] Security regression tests failed (ExitCode: $($secProc.ExitCode))."
        $auditFailed = $true
    } else {
        Write-Host "[PASS] Phase 1b: Security regression suite passed." -ForegroundColor Green
    }
} else {
    Write-Warning "[FAIL] tests/verify_security.ps1 is missing."
    $auditFailed = $true
}

Write-Host "`n[Audit Phase 1c/4] Running Agent Guard v4.4 Regression Suite..." -ForegroundColor White
if (Test-Path $guardTestScript) {
    $guardProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $guardTestScript -NoNewWindow -Wait -PassThru
    if ($guardProc.ExitCode -ne 0) {
        Write-Warning "[FAIL] Agent Guard v4.4 tests failed (ExitCode: $($guardProc.ExitCode))."
        $auditFailed = $true
    } else {
        Write-Host "[PASS] Phase 1c: Agent Guard v4.4 regression suite passed." -ForegroundColor Green
    }
} else {
    Write-Warning "[FAIL] tests/verify_agent_guard.ps1 is missing."
    $auditFailed = $true
}

# --- Phase 2: AI Agent SSOT Rule Synchronization ---
Write-Host "`n[Audit Phase 2/4] Checking AI Agent SSOT Synchronization..." -ForegroundColor White
$syncProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $syncScript, "-Check" -NoNewWindow -Wait -PassThru
if ($syncProc.ExitCode -ne 0) {
    Write-Warning "[FAIL] SSOT rules or skills are out of sync with master."
    $auditFailed = $true
} else {
    Write-Host "[PASS] Phase 2: All AI agent rules and skills are 100% in sync." -ForegroundColor Green
}

# --- Phase 3: Knowledge Graph Health & Topology Analysis ---
Write-Host "`n[Audit Phase 3/4] Analyzing Knowledge Graph Health & Topology..." -ForegroundColor White
if (Test-Path $graphJson) {
    try {
        $jaqCmd = Get-Command jaq -ErrorAction SilentlyContinue
        if ($jaqCmd) {
            $nodeCount = (& jaq ".nodes | length" $graphJson 2>$null).Trim()
            $linkCount = (& jaq ".links | length" $graphJson 2>$null).Trim()
            $orphanNodesJson = & jaq "[(.links[] | .source, .target)] as \$conn | [.nodes[] | .id | select(. as \$id | \$conn | index(\$id) | not)]" $graphJson 2>$null
            $orphanList = $orphanNodesJson | ConvertFrom-Json
            $topHubsJson = & jaq "[.links[] | .source, .target] | group_by(.) | map({name: .[0], count: length}) | sort_by(.count) | reverse | .[0:4]" $graphJson 2>$null
            $topHubs = $topHubsJson | ConvertFrom-Json
        } else {
            $rawGraph = [System.IO.File]::ReadAllText($graphJson, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $nodeCount = $rawGraph.nodes.Count
            $linkCount = $rawGraph.links.Count
            $connected = @{}
            $edgeCounts = @{}
            foreach ($l in $rawGraph.links) {
                $connected[$l.source] = $true
                $connected[$l.target] = $true
                $edgeCounts[$l.source] = ($edgeCounts[$l.source] + 1)
                $edgeCounts[$l.target] = ($edgeCounts[$l.target] + 1)
            }
            $orphanList = @($rawGraph.nodes | Where-Object { -not $connected.ContainsKey($_.id) } | ForEach-Object { $_.id })
            $topHubs = @($edgeCounts.Keys | Sort-Object { $edgeCounts[$_] } -Descending | Select-Object -First 4 | ForEach-Object { [PSCustomObject]@{ name = $_; count = $edgeCounts[$_] } })
        }

        Write-Host "  -> Graph Metrics: $nodeCount nodes, $linkCount edges, $($orphanList.Count) orphan nodes" -ForegroundColor Cyan
        if ($topHubs -and $topHubs.Count -gt 0) {
            $hubNames = ($topHubs | ForEach-Object { "$($_.name) ($($_.count) edges)" }) -join ", "
            Write-Host "  -> Top Architectural Hubs: $hubNames" -ForegroundColor Gray
        }

        $nodeN = 0
        [void][int]::TryParse("$nodeCount", [ref]$nodeN)
        $orphanN = @($orphanList).Count
        $orphanRate = if ($nodeN -gt 0) { [math]::Round(100.0 * $orphanN / $nodeN, 1) } else { 0 }
        $orphanLimit = 40
        Write-Host "  -> Orphan rate: $orphanRate% (fail if > $orphanLimit%)" -ForegroundColor Gray

        $phase3Failed = $false
        if ($orphanRate -gt $orphanLimit) {
            Write-Warning "[FAIL] Orphan rate $orphanRate% exceeds $orphanLimit%. Re-run ``just update-graph`` or inspect disconnected nodes."
            $phase3Failed = $true
        }

        $watchDirs = @(
            (Join-Path $rootDir "configs"),
            (Join-Path $rootDir "scripts"),
            (Join-Path $rootDir "tests")
        )
        $latestSrc = Get-ChildItem -Path $watchDirs -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        foreach ($extra in @("justfile", "AGENTS.md", "install.ps1")) {
            $p = Join-Path $rootDir $extra
            if (Test-Path $p) {
                $item = Get-Item $p
                if (-not $latestSrc -or $item.LastWriteTimeUtc -gt $latestSrc.LastWriteTimeUtc) {
                    $latestSrc = $item
                }
            }
        }
        $graphItem = Get-Item $graphJson
        if ($latestSrc -and $latestSrc.LastWriteTimeUtc -gt $graphItem.LastWriteTimeUtc.AddSeconds(5)) {
            Write-Warning "[FAIL] graph.json is stale vs $($latestSrc.Name) (source $($latestSrc.LastWriteTimeUtc.ToString('o')) > graph $($graphItem.LastWriteTimeUtc.ToString('o'))). Run ``just update-graph``."
            $phase3Failed = $true
        } else {
            Write-Host "  -> Graph freshness: graph.json is current vs configs/scripts/tests" -ForegroundColor Gray
        }

        $slog = Join-Path $rootDir "graphify-out\session-log.jsonl"
        if (Test-Path $slog) {
            $slogLines = @(Get-Content -Path $slog -ErrorAction SilentlyContinue)
            $denyN = 0
            $graphN = 0
            foreach ($line in $slogLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $ev = $line | ConvertFrom-Json
                    if ($ev.denied) { $denyN++ }
                    if ($ev.graph_contact) { $graphN++ }
                } catch {}
            }
            Write-Host "  -> Session log: $($slogLines.Count) events, $graphN graph-contact, $denyN denies" -ForegroundColor Gray
        }

        # Semantic freshness: code-only updates cannot clear docs/image changes (needs_update flag)
        try {
            $checkOut = (& graphify check-update . 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0 -or $checkOut -match "(?i)needs[_ -]?update|pending") {
                Write-Warning "[WARN] Semantic re-extraction pending (docs/images/memory changed). Run ``just update-semantic`` (or ``just watch`` with GRAPHIFY_SEMANTIC_AUTO=1)."
            } else {
                Write-Host "  -> Semantic freshness: no pending re-extraction (check-update clean)" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  -> Semantic freshness: check-update unavailable ($_)" -ForegroundColor DarkGray
        }

        # Work-memory loop: saved results not yet folded into the graph + lessons staleness
        $memDir = Join-Path $rootDir "graphify-out\memory"
        $lessonsFile = Join-Path $rootDir "graphify-out\reflections\LESSONS.md"
        if (Test-Path $memDir) {
            $memFiles = @(Get-ChildItem -Path $memDir -File -ErrorAction SilentlyContinue)
            $pendingMem = @($memFiles | Where-Object { $_.LastWriteTimeUtc -gt $graphItem.LastWriteTimeUtc })
            if ($pendingMem.Count -gt 0) {
                Write-Host "  -> Work-memory: $($pendingMem.Count)/$($memFiles.Count) saved result(s) newer than graph.json (folded on next ``just update-graph``)" -ForegroundColor Gray
            } else {
                Write-Host "  -> Work-memory: $($memFiles.Count) saved result(s), all folded into graph" -ForegroundColor Gray
            }
            $newestMem = $memFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($newestMem -and (-not (Test-Path $lessonsFile) -or (Get-Item $lessonsFile).LastWriteTimeUtc -lt $newestMem.LastWriteTimeUtc)) {
                Write-Warning "[WARN] LESSONS.md is stale vs latest saved result. Run ``just lessons`` (reflect --if-stale)."
            }
        } else {
            Write-Host "  -> Work-memory: empty (seed with ``just remember`` after answering architecture questions)" -ForegroundColor DarkGray
        }

        Write-Host "  -> Fast Exploration: ``just graph query`` | ``just hubs`` | ``just neighbors label`` | ``just lessons``" -ForegroundColor DarkGray
        if ($phase3Failed) {
            $auditFailed = $true
            Write-Warning "[FAIL] Phase 3: Knowledge graph health checks failed."
        } else {
            Write-Host "[PASS] Phase 3: Knowledge graph topology is healthy and verified." -ForegroundColor Green
        }
    } catch {
        Write-Warning "[WARN] Failed to evaluate graph.json: $_"
    }
} else {
    Write-Host "  [SKIP] No graphify-out/graph.json found (gated graph mode)." -ForegroundColor DarkGray
}

# --- Phase 4: Junk & Artifact Scan ---
Write-Host "`n[Audit Phase 4/4] Scanning for Junk, Stale Backups & Conflict Artifacts..." -ForegroundColor White
$foundJunk = @()
foreach ($pat in $junkPatterns) {
    $matched = Get-ChildItem -Path $rootDir -Filter $pat -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" }
    if ($matched) { $foundJunk += $matched }
}

if ($foundJunk.Count -gt 0) {
    Write-Warning "[WARN] Found $($foundJunk.Count) leftover temporary/backup files (Run 'just clean' to resolve):"
    foreach ($jf in $foundJunk) {
        Write-Host "       - $($jf.FullName)" -ForegroundColor Yellow
    }
    $auditFailed = $true
} else {
    Write-Host "[PASS] Phase 4: Zero temporary, backup, or junk files detected." -ForegroundColor Green
}

# --- Final Summary ---
Write-Host "`n=======================================================" -ForegroundColor Cyan
if (-not $auditFailed) {
    Write-Host " AUDIT SUMMARY: 100% CLEAN & VERIFIED (Zero Technical Debt)" -ForegroundColor Green
    Write-Host " Ground truth confirmed. Zero file reading permitted for surveys." -ForegroundColor Green
    Write-Host "=======================================================`n" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host " AUDIT SUMMARY: ISSUES DETECTED - Action Required" -ForegroundColor Red
    Write-Host "=======================================================`n" -ForegroundColor Cyan
    exit 1
}
