#Requires -Version 5.1
<#
.SYNOPSIS
    Windows-safe runner for asset-generator CLI (avoids npx tsx / EBADDEVENGINES).
.EXAMPLE
    .\run.ps1 --print-prompt -g 4 "Theme" --items cells.json --out out
    .\run.ps1 --confirm <token> -g 4 "Theme" --items cells.json --out out
#>
# Passthrough via $args only — no param()/CmdletBinding (PowerShell treats -o as -OutVariable).
$ErrorActionPreference = 'Stop'
$skillRoot = $PSScriptRoot
$tsx = Join-Path $skillRoot 'node_modules\tsx\dist\cli.mjs'
$entry = Join-Path $skillRoot 'src\cli.ts'

if (-not (Test-Path $tsx)) {
    Write-Error "tsx not installed. Run: Set-Location '$skillRoot'; pnpm install"
}

if ($args.Count -eq 0) {
    & node $tsx $entry --help
    exit $LASTEXITCODE
}

& node $tsx $entry @args
exit $LASTEXITCODE
