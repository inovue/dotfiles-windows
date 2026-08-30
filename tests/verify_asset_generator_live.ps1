# Optional live fal.ai smoke for asset-generator (costs API credits).
# Skipped unless -Run or ASSET_GENERATOR_LIVE_TEST=1.

param(
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
$rootDir = Split-Path $PSScriptRoot -Parent
$agDir = Join-Path $rootDir 'configs\agents\skills\asset-generator'

if (-not $Run -and $env:ASSET_GENERATOR_LIVE_TEST -ne '1') {
    Write-Host '[SKIP] asset-generator live API test (set ASSET_GENERATOR_LIVE_TEST=1 or pass -Run)' -ForegroundColor Yellow
    exit 0
}

if (-not $env:FAL_KEY) {
    $userKey = [System.Environment]::GetEnvironmentVariable('FAL_KEY', 'User')
    if ($userKey) { $env:FAL_KEY = $userKey }
}

if (-not $env:FAL_KEY) {
    Write-Host '[FAIL] FAL_KEY not set - run: just setup-fal' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $agDir 'node_modules\tsx\dist\cli.mjs'))) {
    Push-Location $agDir
    $prevCi = $env:CI
    $env:CI = 'true'
    & pnpm install 2>&1 | Out-Null
    $env:CI = $prevCi
    Pop-Location
}

Write-Host '--- asset-generator live API smoke (icons + logos + wordmarks + stability) ---' -ForegroundColor Cyan
Push-Location $agDir
$env:ASSET_GENERATOR_LIVE_TEST = '1'
$env:ASSET_GENERATOR_MIN_SCORE = '70'
if ($env:ASSET_GENERATOR_LIVE_FILTER) {
    Write-Host "  filter: $env:ASSET_GENERATOR_LIVE_FILTER" -ForegroundColor Gray
}
& pnpm exec tsx --test tests/live-api.test.ts
$exit = $LASTEXITCODE
Pop-Location

if ($exit -eq 0) {
    Write-Host '[OK] asset-generator live API smoke passed' -ForegroundColor Green
} else {
    Write-Host "[FAIL] asset-generator live API smoke failed (exit=$exit)" -ForegroundColor Red
}
exit $exit
