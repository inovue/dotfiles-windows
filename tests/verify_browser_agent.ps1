# Browser-agent functional smoke tests (fail -> pass in same batch)
$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot
$runner = Join-Path $rootDir "configs\agents\skills\browser-agent\scripts\browser_runner.py"
$outDir = Join-Path $PSScriptRoot ".tmp\browser-agent"
$capturesDir = Join-Path $outDir "captures"
New-Item -ItemType Directory -Force -Path $outDir, $capturesDir | Out-Null
$env:BROWSER_AGENT_CAPTURE_DIR = $capturesDir

$passedCount = 0
$failedCount = 0

function Assert-BrowserTest {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passedCount++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkGray }
        $script:failedCount++
    }
}

function Invoke-BrowserRunner {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RunnerArgs)
    $stderrPath = Join-Path $outDir "ba-runner-stderr.txt"
    if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }
    $stdout = python $runner @RunnerArgs 2> $stderrPath
    if ($null -eq $stdout) {
        $raw = ""
    } elseif ($stdout -is [array]) {
        $raw = ($stdout -join [Environment]::NewLine).Trim()
    } else {
        $raw = "$stdout".Trim()
    }
    $script:BrowserRunnerLastRaw = $raw
    $errRaw = if (Test-Path $stderrPath) { Get-Content -Raw $stderrPath -ErrorAction SilentlyContinue } else { "" }
    $script:BrowserRunnerStderr = if ($errRaw) { $errRaw.Trim() } else { "" }
    if (-not $raw) {
        throw "browser_runner empty stdout (args: $($RunnerArgs -join ' ')). stderr: $($script:BrowserRunnerStderr)"
    }
    return ($raw | ConvertFrom-Json)
}

Write-Host "`n=== browser-agent smoke tests ===" -ForegroundColor Cyan

# 1. inspect
$inspect = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless

$inspectJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "inspect returns success" ($inspect.status -eq "success") $inspectJson
Assert-BrowserTest "inspect includes auth_state" ($null -ne $inspect.auth_state) $inspect.auth_state

# 2. screenshot
$shotPath = Join-Path $outDir "ba-test-screenshot.png"
$shot = Invoke-BrowserRunner screenshot --url "https://example.com" --profile temp --headless --output $shotPath

$shotJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "screenshot returns success" ($shot.status -eq "success") $shotJson
Assert-BrowserTest "screenshot file exists" (Test-Path $shotPath) $shotPath

# 3. act via --actions-file (Windows-safe)
$actionsFile = Join-Path $outDir "ba-test-actions.json"
@'
[{"type":"wait_for_timeout","milliseconds":200},{"type":"scroll_by","pixels":100}]
'@ | Set-Content -Encoding utf8NoBOM -Path $actionsFile
$act = Invoke-BrowserRunner act --url "https://example.com" --profile temp --headless --actions-file $actionsFile

$actJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "act via actions-file succeeds" ($act.status -eq "success") $actJson

# 4. role locator click
$roleActions = Join-Path $outDir "ba-test-role-actions.json"
@'
[{"type":"click","role":"link","name":"Learn more","timeout":5000}]
'@ | Set-Content -Encoding utf8NoBOM -Path $roleActions
$roleAct = Invoke-BrowserRunner act --url "https://example.com" --profile temp --headless --actions-file $roleActions
$roleJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "act role locator click succeeds" ($roleAct.status -eq "success") $roleJson

# 5. headless defaults (static, no browser launch)
$headlessTest = @"
import importlib.util, pathlib
path = pathlib.Path(r'$($runner.Replace('\','/'))')
spec = importlib.util.spec_from_file_location('br', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.resolve_headless('work', False, False) is False
assert mod.resolve_headless('temp', False, False) is True
print('OK')
"@
$htFile = Join-Path $outDir "headless_test.py"
Set-Content -Encoding utf8 $htFile -Value $headlessTest
$htOut = python $htFile 2>$null | Out-String
Assert-BrowserTest "work profile defaults headed (static)" ($htOut.Trim() -eq "OK") $htOut.Trim()

# 6. setup_profile sanitization (static)
$setupPs1 = Join-Path $rootDir "configs\agents\skills\browser-agent\scripts\setup_profile.ps1"
$setupText = [System.IO.File]::ReadAllText($setupPs1, [System.Text.Encoding]::UTF8)
Assert-BrowserTest "setup_profile.ps1 sanitizes profile name" ($setupText -match "SafeProfile")

# 7. eval via --script-file
$scriptFile = Join-Path $outDir "ba-test-script.js"
Set-Content -Encoding utf8NoBOM -Path $scriptFile -Value "() => document.querySelector('h1')?.innerText || ''"
$eval = Invoke-BrowserRunner eval --url "https://example.com" --profile temp --headless --script-file $scriptFile

$evalJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "eval via script-file succeeds" ($eval.status -eq "success" -and $eval.result -match "Example") $evalJson

# 8. record produces video after context close
$videoPath = Join-Path $outDir "ba-test-record.webm"
$rec = Invoke-BrowserRunner record --url "https://example.com" --profile temp --headed --output $videoPath --scroll-steps 2 --scroll-delay 150

$recJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "record returns success" ($rec.status -eq "success") $recJson
Assert-BrowserTest "record video file exists" ((Test-Path $videoPath) -and ((Get-Item $videoPath).Length -gt 1000)) $videoPath

# 9. auth_state detects login page
$loginUrl = 'data:text/html,<html><title>Sign in</title><body>Please log in to continue</body></html>'
$login = Invoke-BrowserRunner inspect --url $loginUrl --profile temp --headless

$loginJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "auth_state detects login page" ($login.auth_state -eq "likely_login_or_challenge") $login.auth_state
Assert-BrowserTest "login page sets user_action_required" ($login.user_action_required -eq $true) $loginJson
Assert-BrowserTest "login page recommends setup_profile" (($login.recommended_actions -join ' ') -match "setup_profile") $loginJson
Assert-BrowserTest "login inspect sets session_hint" ($login.session_hint -match "Stop unattended") $loginJson

# 10. device preset mobile
$mobile = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless --device mobile

$mobileJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "device mobile preset works" ($mobile.status -eq "success") $mobileJson

# 11. record --headless succeeds (headed fallback when needed)
$videoHeadless = Join-Path $outDir "ba-test-record-headless.webm"
if (Test-Path $videoHeadless) { Remove-Item $videoHeadless -Force }
$recH = Invoke-BrowserRunner record --url "https://example.com" --profile temp --headless --output $videoHeadless --scroll-steps 2 --scroll-delay 150

$recHJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "record with --headless succeeds" ($recH.status -eq "success") $recHJson

# 12. iframe fixture click
$fixture = Join-Path $rootDir "tests\fixtures\browser-agent\iframe-shadow.html"
$fileUrl = "file:///" + ($fixture -replace '\\', '/')
$iframeActions = Join-Path $outDir "ba-test-iframe-actions.json"
@'
[{"type":"click","frame":"#inner","selector":"#go","timeout":5000}]
'@ | Set-Content -Encoding utf8NoBOM -Path $iframeActions
$iframeAct = Invoke-BrowserRunner act --url $fileUrl --profile temp --headless --actions-file $iframeActions
$iframeJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "iframe scoped click succeeds" ($iframeAct.status -eq "success") $iframeJson

# 13. shadow DOM click via shadow_host
$shadowActions = Join-Path $outDir "ba-test-shadow-actions.json"
@'
[{"type":"click","shadow_host":"#shadow-host","selector":"#shadow-btn","timeout":5000}]
'@ | Set-Content -Encoding utf8NoBOM -Path $shadowActions
$shadowAct = Invoke-BrowserRunner act --url $fileUrl --profile temp --headless --actions-file $shadowActions
$shadowJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "shadow_host click succeeds" ($shadowAct.status -eq "success") $shadowJson

# 14. --wait-until networkidle accepted
$wait = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless --wait-until networkidle

$waitJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "wait-until networkidle works" ($wait.status -eq "success" -and $wait.wait_until -eq "networkidle") $waitJson

# 15. profile lock adversarial (static)
$lockTest = @"
import importlib.util, pathlib, tempfile, os
path = pathlib.Path(r'$($runner.Replace('\','/'))')
spec = importlib.util.spec_from_file_location('br', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
td = pathlib.Path(tempfile.mkdtemp(prefix='ba_lock_'))
lock1, err1 = mod.acquire_profile_lock(td)
lock2, err2 = mod.acquire_profile_lock(td)
mod.release_profile_lock(lock1)
lock3, err3 = mod.acquire_profile_lock(td)
mod.release_profile_lock(lock3)
stale = td / mod.PROFILE_LOCK_NAME
stale.write_text('99999999', encoding='utf-8')
cleared = mod._clear_stale_profile_lock(stale)
lock4, err4 = mod.acquire_profile_lock(td)
mod.release_profile_lock(lock4)
assert err2 and not err3 and cleared and not err4, (err1, err2, err3, cleared, err4)
print('OK')
"@
$lockFile = Join-Path $outDir "lock_test.py"
Set-Content -Encoding utf8 $lockFile -Value $lockTest
$lockOut = python $lockFile 2>$null | Out-String
Assert-BrowserTest "profile lock blocks parallel acquire" ($lockOut.Trim() -eq "OK") $lockOut.Trim()

# 16. network JSON capture
$netPath = Join-Path $outDir "ba-network.json"
if (Test-Path $netPath) { Remove-Item $netPath -Force }
$net = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless --network-output $netPath

$netJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "network JSON capture succeeds" ($net.status -eq "success" -and $net.network_event_count -gt 0) $netJson
Assert-BrowserTest "network JSON file exists" (Test-Path $netPath) $netPath

# 17. HAR network capture
$harPath = Join-Path $outDir "ba-network.har"
if (Test-Path $harPath) { Remove-Item $harPath -Force }
$har = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless --network-output $harPath

$harJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "HAR capture succeeds" ($har.status -eq "success" -and $har.network_format -eq "har") $harJson
Assert-BrowserTest "HAR file exists" ((Test-Path $harPath) -and ((Get-Item $harPath).Length -gt 100)) $harPath

# 18. inspect finds shadow DOM elements
$fixture = Join-Path $rootDir "tests\fixtures\browser-agent\iframe-shadow.html"
$fileUrl = "file:///" + ($fixture -replace '\\', '/')
$shadowInspect = Invoke-BrowserRunner inspect --url $fileUrl --profile temp --headless

$shadowInspectJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "inspect reports shadow interactive elements" ($shadowInspect.shadow_interactive_count -ge 1) $shadowInspectJson

# 19. multi-tab act
$tabActions = Join-Path $outDir "ba-test-tab-actions.json"
@'
[{"type":"new_tab","url":"https://example.com"},{"type":"wait_for_timeout","milliseconds":300}]
'@ | Set-Content -Encoding utf8NoBOM -Path $tabActions
$tabAct = Invoke-BrowserRunner act --url "about:blank" --profile temp --headless --actions-file $tabActions
$tabJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "new_tab act succeeds" ($tabAct.status -eq "success" -and $tabAct.current_page.title -match "Example") $tabJson

# 20. cookies export
$cookiePath = Join-Path $outDir "ba-cookies.json"
$cook = Invoke-BrowserRunner cookies --url "https://example.com" --profile temp --headless --export $cookiePath

$cookJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "cookies export succeeds" ($cook.status -eq "success" -and (Test-Path $cookiePath)) $cookJson

# 21. cookies import roundtrip
$roundtripPath = Join-Path $outDir "ba-cookies-roundtrip.json"
@'
[{"name":"ba_roundtrip","value":"ok","domain":"example.com","path":"/"}]
'@ | Set-Content -Encoding utf8NoBOM -Path $roundtripPath
$imported = Invoke-BrowserRunner cookies --url "https://example.com" --profile temp --headless --import $roundtripPath
$importJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "cookies import roundtrip succeeds" ($imported.status -eq "success" -and $imported.imported_count -ge 1) $importJson
Assert-BrowserTest "imported cookie verified in same session" ($imported.verified_count -ge 1 -and ($imported.verified_names -contains "ba_roundtrip")) $importJson

# 22. switch_tab act
$switchActions = Join-Path $outDir "ba-test-switch-tab.json"
@'
[{"type":"new_tab","url":"https://example.com"},{"type":"new_tab","url":"about:blank"},{"type":"switch_tab","index":1},{"type":"wait_for_timeout","milliseconds":200}]
'@ | Set-Content -Encoding utf8NoBOM -Path $switchActions
$switchAct = Invoke-BrowserRunner act --url "about:blank" --profile temp --headless --actions-file $switchActions
$switchJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "switch_tab act succeeds" ($switchAct.status -eq "success" -and $switchAct.current_page.title -match "Example") $switchJson

# 23. close_tab act
$closeActions = Join-Path $outDir "ba-test-close-tab.json"
@'
[{"type":"new_tab","url":"https://example.com"},{"type":"close_tab"},{"type":"wait_for_timeout","milliseconds":200}]
'@ | Set-Content -Encoding utf8NoBOM -Path $closeActions
$closeAct = Invoke-BrowserRunner act --url "about:blank" --profile temp --headless --actions-file $closeActions
$closeJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "close_tab act succeeds" ($closeAct.status -eq "success" -and $closeAct.current_page.url -match "about:blank") $closeJson

# 24. close_tab rejects last tab (adversarial)
$lastTabActions = Join-Path $outDir "ba-test-close-last-tab.json"
@'
[{"type":"close_tab"}]
'@ | Set-Content -Encoding utf8NoBOM -Path $lastTabActions
$lastTabAct = Invoke-BrowserRunner act --url "about:blank" --profile temp --headless --actions-file $lastTabActions
$lastTabJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "close_tab fails on last tab" ($lastTabAct.status -eq "partial_failure" -and $lastTabAct.action_results[0].status -eq "failed") $lastTabJson

# 25. elapsed_ms in JSON output
Assert-BrowserTest "inspect includes elapsed_ms" ($inspect.elapsed_ms -gt 0) "$($inspect.elapsed_ms)"

# 26. switch_tab rejects out-of-range index (adversarial)
$oobTabActions = Join-Path $outDir "ba-test-switch-tab-oob.json"
@'
[{"type":"switch_tab","index":99}]
'@ | Set-Content -Encoding utf8NoBOM -Path $oobTabActions
$oobTabAct = Invoke-BrowserRunner act --url "about:blank" --profile temp --headless --actions-file $oobTabActions
$oobTabJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "switch_tab fails on out-of-range index" ($oobTabAct.status -eq "partial_failure" -and $oobTabAct.action_results[0].status -eq "failed") $oobTabJson

# 27. no dead pierce_shadow hook (static)
$runnerText = [System.IO.File]::ReadAllText($runner, [System.Text.Encoding]::UTF8)
Assert-BrowserTest "runner has no misleading pierce_shadow flag" ($runnerText -notmatch "pierce_shadow")

# 28. localhost dev-server screenshot + act click
$fixtureDir = Join-Path $rootDir "tests\fixtures\browser-agent"
$tcp = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$tcp.Start()
$devPort = $tcp.LocalEndpoint.Port
$tcp.Stop()
$devServer = Start-Process python -ArgumentList @("-m", "http.server", "$devPort", "--bind", "127.0.0.1") `
    -WorkingDirectory $fixtureDir -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 1
try {
    $devUrl = "127.0.0.1:$devPort/dev-page.html"
    $devShotPath = Join-Path $outDir "ba-dev-server.png"
    $dev = Invoke-BrowserRunner screenshot --url $devUrl --profile temp --headless --output $devShotPath
    $devJson = $script:BrowserRunnerLastRaw
    Assert-BrowserTest "localhost dev-server screenshot succeeds" ($dev.status -eq "success" -and $dev.title -match "Dev Server") $devJson
    Assert-BrowserTest "localhost dev-server screenshot file exists" (Test-Path $devShotPath) $devShotPath

    $devActActions = Join-Path $outDir "ba-dev-act-actions.json"
    @'
[{"type":"click","selector":"#action","timeout":5000}]
'@ | Set-Content -Encoding utf8NoBOM -Path $devActActions
    $devAct = Invoke-BrowserRunner act --url $devUrl --profile temp --headless --actions-file $devActActions
    $devActJson = $script:BrowserRunnerLastRaw
    Assert-BrowserTest "localhost dev-server act click succeeds" ($devAct.status -eq "success") $devActJson
} finally {
    if ($devServer -and -not $devServer.HasExited) {
        Stop-Process -Id $devServer.Id -Force -ErrorAction SilentlyContinue
    }
}

# 29. goto_with_retry recovers from transient failure (static)
$retryTest = @"
import asyncio, importlib.util, pathlib
path = pathlib.Path(r'$($runner.Replace('\','/'))')
spec = importlib.util.spec_from_file_location('br', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class FakePage:
    def __init__(self):
        self.calls = 0
    async def goto(self, url, wait_until=None, timeout=None):
        self.calls += 1
        if self.calls == 1:
            raise RuntimeError('transient network error')

async def main():
    page = FakePage()
    await mod.goto_with_retry(page, 'https://example.com', 1000, 3, 'domcontentloaded')
    assert page.calls == 2, page.calls

asyncio.run(main())
print('OK')
"@
$retryFile = Join-Path $outDir "retry_test.py"
Set-Content -Encoding utf8 $retryFile -Value $retryTest
$retryOut = python $retryFile 2>$null | Out-String
Assert-BrowserTest "goto_with_retry succeeds after transient failure" ($retryOut.Trim() -eq "OK") $retryOut.Trim()

# 30. act returns current_page snapshot
Assert-BrowserTest "act includes current_page snapshot" ($null -ne $act.current_page -and $act.current_page.interactive_count -ge 0) $actJson

# 31. auth_state does not treat settings-only page as authenticated (static)
$authTest = @"
import importlib.util, pathlib
path = pathlib.Path(r'$($runner.Replace('\','/'))')
spec = importlib.util.spec_from_file_location('br', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.infer_auth_state('https://example.com', 'Account Settings', 'Update your preferences') == 'unknown'
assert mod.infer_auth_state('https://search.google.com/search-console', 'Search Console', '') == 'likely_authenticated'
print('OK')
"@
$authFile = Join-Path $outDir "auth_test.py"
Set-Content -Encoding utf8 $authFile -Value $authTest
$authOut = python $authFile 2>$null | Out-String
Assert-BrowserTest "auth_state avoids settings-only false positive" ($authOut.Trim() -eq "OK") $authOut.Trim()

# 32. network JSON captures new_tab traffic
$netTabPath = Join-Path $outDir "ba-network-tab.json"
if (Test-Path $netTabPath) { Remove-Item $netTabPath -Force }
$netTabActions = Join-Path $outDir "ba-network-tab-actions.json"
@'
[{"type":"new_tab","url":"https://example.com"},{"type":"wait_for_timeout","milliseconds":300}]
'@ | Set-Content -Encoding utf8NoBOM -Path $netTabActions
$netTab = Invoke-BrowserRunner act --url "about:blank" --profile temp --headless --actions-file $netTabActions --network-output $netTabPath

$netTabJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "network JSON includes new_tab traffic" ($netTab.status -eq "success" -and $netTab.network_event_count -gt 0) $netTabJson

# 33. explicit --profile default is rejected
$defaultReject = Invoke-BrowserRunner inspect --url "https://example.com" --profile default --headless
Assert-BrowserTest "default profile rejected" ($defaultReject.status -eq "error" -and $defaultReject.recommended_profile -eq "temp") $script:BrowserRunnerLastRaw

# 34. manual SSO smoke script skips by default
$ssoSkip = pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "verify_browser_agent_sso.ps1") 2>$null | Out-String
Assert-BrowserTest "manual SSO smoke skips without flag" ($ssoSkip -match "\[SKIP\]")

# 35. argparse default profile is temp (static)
$dpFile = Join-Path $outDir "default_profile_test.py"
Set-Content -Encoding utf8 $dpFile -Value @"
import pathlib
path = pathlib.Path(r'$($runner.Replace('\','/'))')
text = path.read_text(encoding='utf-8')
assert '--profile", default="temp"' in text, 'expected temp default'
print('OK')
"@
$dpOut = python $dpFile 2>$null | Out-String
Assert-BrowserTest "argparse default profile is temp" ($dpOut.Trim() -eq "OK") $dpOut.Trim()

# 36. omitted --profile uses temp (headless, no profile_hint)
$omit = Invoke-BrowserRunner inspect --url "https://example.com" --headless

$omitJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "omitted profile runs headless temp" ($omit.status -eq "success" -and $omit.headless -eq $true -and $null -eq $omit.profile_hint) $omitJson

# 37. SPA screenshot --spa-ready waits for hydration
$spaFixture = Join-Path $rootDir "tests\fixtures\browser-agent\spa-lazy.html"
$spaUrl = "file:///" + ($spaFixture -replace '\\', '/')
$spaShotPath = Join-Path $outDir "ba-spa-ready.png"
$spa = Invoke-BrowserRunner screenshot --url $spaUrl --profile temp --headless --spa-ready  --wait-for-function "document.getElementById('title')?.innerText === 'SPA Ready'"  --output $spaShotPath

$spaJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "spa-ready screenshot succeeds" ($spa.status -eq "success" -and $spa.capture_hint -eq "SPA Ready") $spaJson
Assert-BrowserTest "spa-ready reports prep steps" ($spa.screenshot_prep.spa_ready -eq $true -and $spa.screenshot_prep.disable_animations -eq $true) $spaJson

# 38. SPA lazy-load after prefetch-scroll
$spaLazyPath = Join-Path $outDir "ba-spa-lazy.png"
$spaLazy = Invoke-BrowserRunner screenshot --url $spaUrl --profile temp --headless --spa-ready --prefetch-scroll  --wait-for-function "document.getElementById('lazy-status')?.innerText === 'lazy-loaded'"  --output $spaLazyPath

$spaLazyJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "prefetch-scroll captures lazy content" ($spaLazy.status -eq "success" -and $spaLazy.screenshot_prep.prefetch_scroll -eq $true) $spaLazyJson

# 39. default capture path (no --output)
$default = Invoke-BrowserRunner screenshot --url "https://example.com" --profile temp --headless

$defaultJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "default screenshot uses capture_default" ($default.capture_default -eq $true) $defaultJson
Assert-BrowserTest "default screenshot under captures base" ($default.screenshot_path.StartsWith($capturesDir)) $default.screenshot_path
Assert-BrowserTest "default screenshot file exists" (Test-Path $default.screenshot_path) $default.screenshot_path
Assert-BrowserTest "capture_dir is parent of screenshot_path" ($default.capture_dir -eq (Split-Path -Parent $default.screenshot_path)) $defaultJson
Assert-BrowserTest "captures_base matches env" ($default.captures_base -eq $capturesDir) $default.captures_base

# 40. --output-dir overrides base for default naming
$customBase = Join-Path $outDir "custom-captures"
New-Item -ItemType Directory -Force -Path $customBase | Out-Null
$custom = Invoke-BrowserRunner screenshot --url "https://example.com" --profile temp --headless --output-dir $customBase

$customJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "output-dir default path succeeds" ($custom.status -eq "success" -and $custom.capture_default -eq $true) $customJson
Assert-BrowserTest "output-dir path under custom base" ($custom.screenshot_path.StartsWith($customBase)) $custom.screenshot_path

# 41. route slug in default screenshot filename
$route = Invoke-BrowserRunner screenshot --url "https://example.com/docs/api/v1" --profile temp --headless

$routeJson = $script:BrowserRunnerLastRaw
$routeLeaf = Split-Path -Leaf $route.screenshot_path
Assert-BrowserTest "route slug in screenshot filename" ($routeLeaf -match "example-com--docs-api-v1") $routeLeaf
Assert-BrowserTest "capture_route_slug in JSON" ($route.capture_route_slug -eq "example-com--docs-api-v1") $route.capture_route_slug

# 42. route slug in default record filename
$recDefault = Invoke-BrowserRunner record --url "https://example.com/docs/guide" --profile temp --headless --scroll-steps 1 --scroll-delay 100

$recDefaultJson = $script:BrowserRunnerLastRaw
$recLeaf = Split-Path -Leaf $recDefault.video_path
Assert-BrowserTest "route slug in record filename" ($recLeaf -match "example-com--docs-guide") $recLeaf
Assert-BrowserTest "record capture_route_slug in JSON" ($recDefault.capture_route_slug -eq "example-com--docs-guide") $recDefault.capture_route_slug

# 43. --all-devices screenshot captures mobile, tablet, desktop
$allDev = Invoke-BrowserRunner screenshot --url "https://example.com/docs/api/v1" --profile temp --headless --all-devices

$allDevJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "all-devices screenshot succeeds" ($allDev.status -eq "success" -and $allDev.multi_device -eq $true) $allDevJson
Assert-BrowserTest "all-devices returns three captures" ($allDev.captures.Count -eq 3) $allDevJson
Assert-BrowserTest "all-devices includes mobile capture" ($allDev.captures.device -contains "mobile") $allDevJson
Assert-BrowserTest "all-devices mobile filename tagged" (($allDev.captures | Where-Object { $_.device -eq "mobile" }).screenshot_path -match "mobile-example-com--docs-api-v1") $allDevJson

# 44. --devices mobile,desktop partial set
$partialDev = Invoke-BrowserRunner screenshot --url "https://example.com/about" --profile temp --headless --devices "mobile,desktop"

$partialDevJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "partial devices screenshot succeeds" ($partialDev.status -eq "success" -and $partialDev.captures.Count -eq 2) $partialDevJson
Assert-BrowserTest "partial devices tags filenames" ($partialDev.captures.screenshot_path -match "mobile-" -and $partialDev.captures.screenshot_path -match "desktop-") $partialDevJson

# 45. record scroll-mode step (viewport pause)
$tallFixture = Join-Path $rootDir "tests\fixtures\browser-agent\tall-page.html"
$tallUrl = "file:///$($tallFixture -replace '\\', '/')"
$videoStepPath = Join-Path $outDir "ba-test-record-step.webm"
if (Test-Path $videoStepPath) { Remove-Item $videoStepPath -Force }
$stepRec = Invoke-BrowserRunner record --url $tallUrl --profile temp --headless --scroll-mode step  --scroll-steps 3 --scroll-duration-ms 400 --scroll-pause-ms 100 --output $videoStepPath

$stepRecJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "step scroll mode succeeds" ($stepRec.status -eq "success" -and $stepRec.scroll_mode -eq "step") $stepRecJson
Assert-BrowserTest "step scroll performs viewport jumps" ($stepRec.scroll_steps_performed -eq 3 -and $stepRec.scroll_duration_ms -eq 400) $stepRec.scroll_steps_performed
Assert-BrowserTest "step scroll uses linear motion" ($stepRec.scroll_easing -eq "linear") $stepRec.scroll_easing
Assert-BrowserTest "step scroll video file exists" ((Test-Path $videoStepPath) -and ((Get-Item $videoStepPath).Length -gt 1000)) $videoStepPath

# 46. record scroll-mode step full-page reaches tall fixture bottom
$videoStepFullPath = Join-Path $outDir "ba-test-record-step-full.webm"
if (Test-Path $videoStepFullPath) { Remove-Item $videoStepFullPath -Force }
$stepFull = Invoke-BrowserRunner record --url $tallUrl --profile temp --headless --scroll-mode step --full-page  --scroll-pause-ms 80 --output $videoStepFullPath

$stepFullJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "step full-page scroll succeeds" ($stepFull.status -eq "success" -and $stepFull.scroll_mode -eq "step") $stepFullJson
Assert-BrowserTest "step full-page scrolls multiple screens" ($stepFull.scroll_steps_performed -ge 4) $stepFull.scroll_steps_performed

# 47. smooth remains default scroll mode
Assert-BrowserTest "smooth mode is default" ($rec.scroll_mode -eq "smooth") $rec.scroll_mode

# 48. record --full-page auto SPA prep (record_prep)
$tallFixture = Join-Path $rootDir "tests\fixtures\browser-agent\tall-page.html"
$tallUrl = "file:///$($tallFixture -replace '\\', '/')"
$recPrepPath = Join-Path $outDir "ba-test-record-prep.webm"
if (Test-Path $recPrepPath) { Remove-Item $recPrepPath -Force }
$recPrep = Invoke-BrowserRunner record --url $tallUrl --profile temp --headless --full-page --scroll-mode step  --scroll-steps 1 --scroll-duration-ms 200 --scroll-pause-ms 100 --output $recPrepPath

$recPrepJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "record full-page includes record_prep" ($recPrep.record_prep.spa_ready -eq $true -and $recPrep.record_prep.prefetch_full_document -eq $true) $recPrepJson

# 49. screenshot --full-page auto spa-ready without explicit flag
$autoSpaPath = Join-Path $outDir "ba-auto-spa-full.png"
$autoSpa = Invoke-BrowserRunner screenshot --url "https://example.com" --profile temp --headless --full-page --output $autoSpaPath

$autoSpaJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "full-page auto enables spa-ready" ($autoSpa.screenshot_prep.spa_ready -eq $true) $autoSpaJson

# 50. act partial_failure escalates to agent
$failActions = Join-Path $outDir "ba-test-fail-actions.json"
@'
[{"type":"click","selector":"#does-not-exist"}]
'@ | Set-Content -Encoding utf8NoBOM -Path $failActions
$failAct = Invoke-BrowserRunner act --url "https://example.com" --profile temp --headless --actions-file $failActions

$failActJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "act failure sets user_action_required" ($failAct.user_action_required -eq $true) $failActJson
Assert-BrowserTest "act failure recommends inspect snapshot" (($failAct.recommended_actions -join ' ') -match "current_page") $failActJson

# 51. broken lazy images trigger capture incomplete guidance
$brokenFixture = Join-Path $rootDir "tests\fixtures\browser-agent\lazy-broken-images.html"
$brokenUrl = "file:///$($brokenFixture -replace '\\', '/')"
$brokenPath = Join-Path $outDir "ba-broken-lazy.png"
$broken = Invoke-BrowserRunner screenshot --url $brokenUrl --profile temp --headless --full-page --output $brokenPath

$brokenJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "broken lazy images report pending after prime" ($broken.screenshot_prep.images_pending_after_prime -gt 0) $brokenJson
Assert-BrowserTest "broken lazy images set capture_incomplete" ($broken.capture_incomplete -eq $true) $brokenJson
Assert-BrowserTest "pending images recommend review" (($broken.recommended_actions -join ' ') -match "incomplete") $brokenJson
Assert-BrowserTest "capture_incomplete success sets session_hint" ($broken.session_hint -match "verify visually") $brokenJson

# 52. profile lock error enriches guidance (static)
$lockEnrichFile = Join-Path $outDir "lock_enrich_test.py"
Set-Content -Encoding utf8 $lockEnrichFile -Value @"
import argparse, importlib.util, json, sys
path = r'$($runner.Replace('\','/'))'
spec = importlib.util.spec_from_file_location('ba', path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
out = {'status': 'error', 'error': "Profile 'work' is locked (pid 999). Close Chrome windows using this profile."}
args = argparse.Namespace(profile='work', command='inspect')
mod.enrich_output_guidance(out, args)
assert out.get('user_action_required') is True
assert any('Close Chrome' in a for a in out.get('recommended_actions', []))
print('OK')
"@
$lockEnrichOut = python $lockEnrichFile 2>$null | Out-String
Assert-BrowserTest "profile lock error enriches guidance" ($lockEnrichOut.Trim() -eq "OK") $lockEnrichOut.Trim()

# 53. batch reuses one browser session for multiple steps
$batchFile = Join-Path $outDir "ba-test-batch.json"
@'
[
  {"name":"ex1","command":"inspect","url":"https://example.com"},
  {"name":"ex2","command":"inspect","url":"https://example.com/docs"}
]
'@ | Set-Content -Encoding utf8NoBOM -Path $batchFile
$batch = Invoke-BrowserRunner batch --batch-file $batchFile --profile temp --headless

$batchJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "batch succeeds" ($batch.status -eq "success") $batchJson
Assert-BrowserTest "batch sets session_reused" ($batch.session_reused -eq $true) $batchJson
Assert-BrowserTest "batch runs two inspect steps" ($batch.step_count -eq 2 -and $batch.results.Count -eq 2) $batchJson
Assert-BrowserTest "batch session_mode single_launch" ($batch.session_mode -eq "single_launch") $batchJson

# 54. batch inspect + screenshot in one session
$batchCapFile = Join-Path $outDir "ba-test-batch-cap.json"
$batchCapPath = Join-Path $outDir "ba-batch-cap.png"
@'
[
  {"name":"cap","command":"inspect","url":"https://example.com"},
  {"name":"cap","command":"screenshot","url":"https://example.com","output":"PLACEHOLDER"}
]
'@.Replace("PLACEHOLDER", ($batchCapPath -replace '\\', '/')) | Set-Content -Encoding utf8NoBOM -Path $batchCapFile
$batchCap = Invoke-BrowserRunner batch --batch-file $batchCapFile --profile temp --headless

$batchCapJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "batch screenshot step succeeds" ($batchCap.status -eq "success") $batchCapJson
Assert-BrowserTest "batch screenshot file exists" (Test-Path $batchCapPath) $batchCapPath

# 55. --cdp-url flag exists (static)
$cdpFile = Join-Path $outDir "cdp_flag_test.py"
Set-Content -Encoding utf8 $cdpFile -Value @"
import pathlib
text = pathlib.Path(r'$($runner.Replace('\','/'))').read_text(encoding='utf-8')
assert '--cdp-url' in text and 'BROWSER_AGENT_CDP_URL' in text
print('OK')
"@
$cdpOut = python $cdpFile 2>$null | Out-String
Assert-BrowserTest "runner supports cdp-url attach" ($cdpOut.Trim() -eq "OK") $cdpOut.Trim()

# 55b. invalid CDP endpoint returns error JSON (no Chrome on port 1)
$cdpBad = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless --cdp-url "http://127.0.0.1:1"
Assert-BrowserTest "invalid cdp-url returns error status" ($cdpBad.status -eq "error") $script:BrowserRunnerLastRaw
Assert-BrowserTest "invalid cdp-url includes error message" ([bool]$cdpBad.error) $script:BrowserRunnerLastRaw
Assert-BrowserTest "invalid cdp-url recommends debugging port" (($cdpBad.recommended_actions -join ' ') -match "remote-debugging-port") $script:BrowserRunnerLastRaw

# 56. batch login step sets user_action_required
$batchLoginFile = Join-Path $outDir "ba-batch-login.json"
$loginPageUrl = 'data:text/html,<html><title>Sign in</title><body>Please log in</body></html>'
@"
[{"name":"login","command":"inspect","url":"$loginPageUrl"}]
"@ | Set-Content -Encoding utf8NoBOM -Path $batchLoginFile
$batchLogin = Invoke-BrowserRunner batch --batch-file $batchLoginFile --profile temp --headless

$batchLoginJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "batch login sets user_action_required" ($batchLogin.user_action_required -eq $true) $batchLoginJson
Assert-BrowserTest "batch login sets auth_state" ($batchLogin.auth_state -eq "likely_login_or_challenge") $batchLoginJson

# 57. batch invalid file returns error JSON
$badBatch = Invoke-BrowserRunner batch --batch-file (Join-Path $outDir "missing-batch.json") --profile temp
Assert-BrowserTest "batch missing file errors" ($badBatch.status -eq "error") $script:BrowserRunnerLastRaw

# 58. batch continues after step failure (partial_failure)
$batchFailFile = Join-Path $outDir "ba-batch-fail.json"
@'
[
  {"name":"ok","command":"inspect","url":"https://example.com"},
  {"name":"bad","command":"eval","url":"https://example.com"}
]
'@ | Set-Content -Encoding utf8NoBOM -Path $batchFailFile
$batchFail = Invoke-BrowserRunner batch --batch-file $batchFailFile --profile temp --headless

$batchFailJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "batch eval missing script partial_failure" ($batchFail.status -eq "partial_failure") $batchFailJson
Assert-BrowserTest "batch partial_failure sets user_action_required" ($batchFail.user_action_required -eq $true) $batchFailJson
Assert-BrowserTest "batch reports failed_step_count" ($batchFail.failed_step_count -eq 1 -and $batchFail.steps_succeeded -eq 1) $batchFailJson
Assert-BrowserTest "batch runs both steps" ($batchFail.step_count -eq 2) $batchFailJson

# 59. inspect reports interactive_truncated at cap
$manyFixture = Join-Path $rootDir "tests\fixtures\browser-agent\many-buttons.html"
$manyUrl = "file:///$($manyFixture -replace '\\', '/')"
$many = Invoke-BrowserRunner inspect --url $manyUrl --profile temp --headless

$manyJson = $script:BrowserRunnerLastRaw
Assert-BrowserTest "many-buttons inspect succeeds" ($many.status -eq "success") $manyJson
Assert-BrowserTest "many-buttons reports truncated" ($many.interactive_truncated -eq $true) $manyJson
Assert-BrowserTest "many-buttons at cap count" ($many.interactive_count -eq 90) $many.interactive_count

# 60. setup_profile default is work (static)
$spText = Get-Content -Raw -Encoding UTF8 (Join-Path $rootDir "configs\agents\skills\browser-agent\scripts\setup_profile.ps1")
Assert-BrowserTest "setup_profile defaults to work" ($spText -match 'ProfileName = "work"')

# 61. stdout-only JSON contract (stderr must not break agent parsing)
$stderrPath = Join-Path $outDir "ba-stdout-contract-stderr.txt"
if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }
$stdoutOnly = Invoke-BrowserRunner inspect --url "https://example.com" --profile temp --headless
$stderrBytes = if (Test-Path $stderrPath) { (Get-Item $stderrPath).Length } else { 0 }
Assert-BrowserTest "inspect stdout parses as JSON" ($stdoutOnly.status -eq "success") $script:BrowserRunnerLastRaw
Assert-BrowserTest "inspect stderr empty on success" ($stderrBytes -eq 0) "stderr length=$stderrBytes"

# 62. cookies export marks sensitive + recommends caution
$cookWarn = Invoke-BrowserRunner cookies --url "https://example.com" --profile temp --headless --export (Join-Path $outDir "ba-cookies-warn.json")
Assert-BrowserTest "cookies export sensitive_export flag" ($cookWarn.sensitive_export -eq $true) $script:BrowserRunnerLastRaw
Assert-BrowserTest "cookies export recommends never commit" (($cookWarn.recommended_actions -join ' ') -match "Never commit") $script:BrowserRunnerLastRaw

Write-Host "`nSummary: $passedCount passed, $failedCount failed" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
if ($failedCount -gt 0) { exit 1 }
