# Manual SSO smoke - optional, never required for just test / CI
param([switch]$Run)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $rootDir "configs\agents\skills\browser-agent\scripts\browser_runner.py"
$outDir = Join-Path $PSScriptRoot ".tmp\browser-agent"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$enabled = $Run.IsPresent -or ($env:BROWSER_AGENT_SSO_TEST -eq "1")
$profileDir = Join-Path $HOME ".chrome-profiles\work"
$matrixReport = Join-Path $outDir "sso-matrix-report.json"

Write-Host "`n=== browser-agent SSO matrix (batch session) ===" -ForegroundColor Cyan

if (-not $enabled) {
    Write-Host "[SKIP] Set BROWSER_AGENT_SSO_TEST=1 or run: just test-browser-sso-run" -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $profileDir)) {
    Write-Host "[SKIP] No work profile at $profileDir - run setup_profile.ps1 first" -ForegroundColor Yellow
    exit 0
}

$gscShot = Join-Path $outDir "sso-gsc.png"
$cfShot = Join-Path $outDir "sso-cf.png"
$batchTemplate = Join-Path $rootDir "tests\fixtures\browser-agent\sso-matrix.batch.json"
$batchFile = Join-Path $outDir "sso-matrix.batch.json"
$template = Get-Content -Raw -Encoding UTF8 $batchTemplate
$template.Replace("PLACEHOLDER_GSC", ($gscShot -replace '\\', '/')).Replace("PLACEHOLDER_CF", ($cfShot -replace '\\', '/')) |
    Set-Content -Encoding utf8NoBOM -Path $batchFile

$cdpArg = @()
if ($env:BROWSER_AGENT_CDP_URL) {
    $cdpArg = @("--cdp-url", $env:BROWSER_AGENT_CDP_URL)
    Write-Host "CDP attach: $($env:BROWSER_AGENT_CDP_URL)" -ForegroundColor DarkGray
}

$batchJson = python $runner batch --batch-file $batchFile --profile work @cdpArg 2>$null | Out-String
$batch = $batchJson | ConvertFrom-Json

if ($batch.status -ne "success" -and $batch.status -ne "partial_failure") {
    Write-Host "[FAIL] batch command failed" -ForegroundColor Red
    Write-Host $batchJson -ForegroundColor DarkGray
    exit 1
}

if (-not $batch.session_reused -or $batch.step_count -ne 4) {
    Write-Host "[FAIL] expected session_reused=true and step_count=4" -ForegroundColor Red
    Write-Host $batchJson -ForegroundColor DarkGray
    exit 1
}

Write-Host "session_mode: $($batch.session_mode) elapsed_ms: $($batch.elapsed_ms)" -ForegroundColor DarkGray

$matrix = @()
$failed = 0
$inspectResults = $batch.results | Where-Object { $_.command -eq "inspect" }
foreach ($inspect in $inspectResults) {
    $name = $inspect.name
    $shot = $batch.results | Where-Object { $_.command -eq "screenshot" -and $_.name -eq $name } | Select-Object -First 1
    $shotOk = $shot -and $shot.status -eq "success" -and (Test-Path $shot.screenshot_path)
    $row = [ordered]@{
        name           = $name
        url            = $inspect.url
        auth_state     = $inspect.auth_state
        auth_assertion = if ($inspect.auth_state -eq "likely_login_or_challenge") { "warn_login" }
                         elseif ($inspect.auth_state -eq "likely_authenticated") { "hint_authenticated" }
                         else { "unknown_review_screenshot" }
        inspect_ms     = $inspect.step_elapsed_ms
        screenshot     = if ($shotOk) { $shot.screenshot_path } else { $null }
        screenshot_ok  = $shotOk
        status         = if ($inspect.status -eq "success" -and $shotOk) { "screenshot_ok" } else { "failed" }
        warn           = ($inspect.auth_state -eq "likely_login_or_challenge")
    }
    $matrix += $row
    Write-Host "`n--- $name ---" -ForegroundColor DarkCyan
    Write-Host "  auth_state: $($inspect.auth_state) inspect_ms: $($inspect.step_elapsed_ms)"
    if (-not $shotOk) {
        Write-Host "  [FAIL] screenshot missing or failed" -ForegroundColor Red
        $failed++
        continue
    }
    Write-Host "  [PASS] screenshot: $($shot.screenshot_path)" -ForegroundColor Green
    if ($row.warn) {
        Write-Host "  [WARN] auth_assertion=$($row.auth_assertion) - review screenshot (captured != logged in)" -ForegroundColor Yellow
    }
}

$report = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    profile      = "work"
    session_mode = $batch.session_mode
    elapsed_ms   = $batch.elapsed_ms
    matrix       = $matrix
}
($report | ConvertTo-Json -Depth 6) | Set-Content -Encoding utf8NoBOM -Path $matrixReport
Write-Host "`nMatrix report: $matrixReport" -ForegroundColor DarkGray

$captured = @($matrix | Where-Object { $_.screenshot_ok -eq $true }).Count
Write-Host "`nSummary: $captured/$($matrix.Count) targets screenshot_ok (auth warnings allowed; not login proof)" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
