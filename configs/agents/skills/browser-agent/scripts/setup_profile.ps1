param (
    [string]$ProfileName = "default"
)

$baseDir = Join-Path $HOME ".chrome-profiles"
$profilePath = Join-Path $baseDir $ProfileName

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType Directory -Force -Path $profilePath | Out-Null
    Write-Host "[+] Created new profile directory: $profilePath" -ForegroundColor Green
}

$chromeCmd = Get-Command chrome -ErrorAction SilentlyContinue
$chromePaths = @(
    $(if ($chromeCmd) { $chromeCmd.Source }),
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
) | Where-Object { $_ -and (Test-Path $_) }

$chromeExe = $chromePaths | Select-Object -First 1

if (-not $chromeExe) {
    Write-Error "Google Chrome executable not found. Please ensure Chrome is installed."
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Launching Real Google Chrome with Profile: $ProfileName" -ForegroundColor Cyan
Write-Host " Path: $profilePath" -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "1. Log into your required services (Google, Cloudflare, etc.)" -ForegroundColor Yellow
Write-Host "2. Once logged in, simply CLOSE the Chrome window." -ForegroundColor Yellow
Write-Host "3. The session cookies and auth tokens will be saved automatically." -ForegroundColor Green
Write-Host ""

& $chromeExe --user-data-dir="$profilePath" --no-first-run --no-default-browser-check
