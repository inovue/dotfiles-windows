# ascii-chat-diagrams skill + helper regression (fail->pass contract)
$ErrorActionPreference = 'Stop'
$rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$helper = Join-Path $rootDir "configs\agents\skills\ascii-chat-diagrams\scripts\ascii_diagram_helper.py"
$examplesDir = Join-Path $rootDir "configs\agents\skills\ascii-chat-diagrams\examples"
$tmpDir = Join-Path $rootDir "tests\.tmp\ascii-chat-diagrams"
New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null

$passed = 0
$failed = 0

function Assert-Check {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkRed }
        $script:failed++
    }
}

Write-Host "`n=== ascii-chat-diagrams verification ===" -ForegroundColor Cyan

# --- helper smoke ---
$draftPath = Join-Path $tmpDir "draft.txt"
python -c "open(r'$draftPath','w',encoding='utf-8').write('hello world\nsecond line CJK \u65e5\u672c\u8a9e')" | Out-Null
$outPath = Join-Path $tmpDir "autofit-out.txt"
$outLines = python $helper autofit --mode pc --file $draftPath
[System.IO.File]::WriteAllText($outPath, ($outLines -join "`n"), [System.Text.UTF8Encoding]::new($false))
$validateOut = python $helper validate --mode pc --file $outPath 2>&1 | Out-String
Assert-Check "autofit CJK draft -> validate PASS" ($validateOut -match '\[PASS\]')

$frameOut = python $helper frame --mode sp --title "Panel" --text "row one" 2>&1 | Out-String
Assert-Check "frame titled box" ($frameOut -match '\[ Panel \]' -and $frameOut -match 'row one')

$chartOut = python $helper barchart --labels "A,B,C" --values "10,80,45" --width 40 2>&1 | Out-String
Assert-Check "barchart renders bars" (($chartOut -split "`n").Count -ge 3 -and $chartOut.Trim().Length -gt 10)

$tableOut = python $helper table --headers "Name,Score" --rows "Alice,90|Bob,72" --width 40 2>&1 | Out-String
Assert-Check "table command" ($tableOut -match 'Name' -and $tableOut -match 'Alice')

$sparkOut = python $helper sparkline --values "1,3,2,5,4,6" --width 20 2>&1 | Out-String
Assert-Check "sparkline command" ($sparkOut.Trim().Length -ge 6)

# --- example files must validate ---
$exampleMap = @{
    "ascii-sp-dashboard.md"       = "sp"
    "ascii-comparison-table.md"   = @{ mode = "pc"; width = 48 }
    "ascii-flow-login.md"         = "flow"
    "pc-dashboard.md"             = "pc"
    "tablet-two-column.md"        = "tablet"
    "sp-mobile-stack.md"          = "sp"
    "user-flow-diagram.md"        = "flow"
}

$extractPy = Join-Path $tmpDir "extract_block.py"
@'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r"```text\s*\n(.*?)```", text, re.S)
if not m:
    sys.exit(2)
pathlib.Path(sys.argv[2]).write_text(m.group(1).strip("\n"), encoding="utf-8")
'@ | Set-Content -Path $extractPy -Encoding utf8

foreach ($kv in $exampleMap.GetEnumerator()) {
    $exFile = Join-Path $examplesDir $kv.Key
    $blockPath = Join-Path $tmpDir ("ex-" + $kv.Key + ".txt")
    python $extractPy $exFile $blockPath
    if ($LASTEXITCODE -ne 0) {
        Assert-Check "example has text block: $($kv.Key)" $false "no text block"
        continue
    }
    $modeName = $kv.Value
    $validateArgs = @("validate", "--file", $blockPath)
    if ($modeName -is [hashtable]) {
        $validateArgs += @("--mode", $modeName.mode, "--width", $modeName.width)
        $label = "$($modeName.mode) w=$($modeName.width)"
    } else {
        $validateArgs += @("--mode", $modeName)
        $label = $modeName
    }
    $v = python $helper @validateArgs 2>&1 | Out-String
    Assert-Check "example validates: $($kv.Key) ($label)" ($v -match '\[PASS\]') ($v -split "`n" | Select-Object -Last 3 | Out-String)
}

# --- already-framed must not double-wrap ---
$framedPath = Join-Path $tmpDir "framed.txt"
python $extractPy (Join-Path $examplesDir "sp-mobile-stack.md") $framedPath | Out-Null
$fit1 = python $helper autofit --mode sp --file $framedPath
$fit2Path = Join-Path $tmpDir "fit2.txt"
[System.IO.File]::WriteAllText($fit2Path, ($fit1 -join "`n"), [System.Text.UTF8Encoding]::new($false))
$lineCount1 = (Get-Content $framedPath | Measure-Object -Line).Lines
$lineCount2 = (Get-Content $fit2Path | Measure-Object -Line).Lines
Assert-Check "autofit does not double-wrap framed diagram" ($lineCount1 -eq $lineCount2) "lines $lineCount1 -> $lineCount2"

# --- adversarial: multi-column autofit must validate ---
python -c "open(r'$tmpDir\mc-draft.txt','w',encoding='utf-8').write('\n'.join(['| left col | right col with overflow text |'.replace('|','│'),'| more left | more right content here |'.replace('|','│')]))" | Out-Null
$mcOut = python $helper autofit --mode pc --file (Join-Path $tmpDir "mc-draft.txt") 2>&1 | Out-String
$mcValidate = python $helper validate --mode pc --text ($mcOut.Trim()) 2>&1 | Out-String
Assert-Check "multi-column autofit validates at W=80" ($mcValidate -match '\[PASS\]')

# --- adversarial: --split off-by-one auto-corrects ---
python -c "open(r'$tmpDir\split-tablet.txt','w',encoding='utf-8').write('\n'.join(['\u2502 A: Sidebar nav           \u2502 B: Top tabs only           \u2502','\u2502 + more content           \u2502 + simpler header           \u2502']))" | Out-Null
$splitTablet = python $helper autofit --mode tablet --split 26,28 --file (Join-Path $tmpDir "split-tablet.txt") 2>&1 | Out-String
Assert-Check "--split 26,28 tablet W=56 validates" ($LASTEXITCODE -eq 0 -and ($splitTablet -split "`n" | Where-Object { $_ -match 'width =' }).Count -eq 0)

python -c "open(r'$tmpDir\split-pc.txt','w',encoding='utf-8').write('\n'.join(['\u2502 Nav sidebar    \u2502 Main content area with details \u2502','\u2502 Dashboard      \u2502 Charts and tables go here         \u2502']))" | Out-Null
$splitPc = python $helper autofit --mode pc --split 22,54 --file (Join-Path $tmpDir "split-pc.txt") 2>&1 | Out-String
Assert-Check "--split 22,54 pc W=80 validates" ($LASTEXITCODE -eq 0 -and ($splitPc -split "`n" | Where-Object { $_ -match 'width =' }).Count -eq 0)

# --- adversarial: frame interior horizontal rule ---
$frameSepPath = Join-Path $tmpDir "frame-sep.txt"
python -c "open(r'$frameSepPath','w',encoding='utf-8').write('\n'.join(['Alert: disk 90%','\u2500'*20,'Alert: CPU high']))" | Out-Null
$frameSepOut = python $helper frame --mode sp --title "Notifications" --file $frameSepPath 2>&1 | Out-String
$frameSepFile = Join-Path $tmpDir "frame-sep-out.txt"
[System.IO.File]::WriteAllText($frameSepFile, $frameSepOut.Trim(), [System.Text.UTF8Encoding]::new($false))
$frameSepValidate = python $helper validate --mode sp --file $frameSepFile 2>&1 | Out-String
Assert-Check "frame interior horizontal rule validates" ($frameSepValidate -match '\[PASS\]' -and $frameSepOut -notmatch '─+\s+\│')

# --- adversarial: invalid inputs exit cleanly (no traceback) ---
$badChart = python $helper barchart --labels "A" --values "notnum" --width 20 2>&1 | Out-String
Assert-Check "barchart rejects invalid values" ($LASTEXITCODE -ne 0 -and $badChart -match 'invalid number')

$badTable = python $helper table --headers "A,B" --rows "onlyone" --width 30 2>&1 | Out-String
Assert-Check "table rejects column mismatch" ($LASTEXITCODE -ne 0 -and $badTable -match 'expected 2')

$badSplit = python $helper autofit --mode sp --split "abc,def" --text "x" 2>&1 | Out-String
Assert-Check "invalid --split exits cleanly" ($LASTEXITCODE -eq 2 -and $badSplit -match 'invalid column width' -and $badSplit -notmatch 'Traceback')

$longTitle = python $helper frame --mode sp --title "VeryLongTitleThatOverflows" --text "x" 2>&1 | Out-String
$longTitleFile = Join-Path $tmpDir "long-title-out.txt"
[System.IO.File]::WriteAllText($longTitleFile, $longTitle.Trim(), [System.Text.UTF8Encoding]::new($false))
$longTitleValidate = python $helper validate --mode sp --file $longTitleFile 2>&1 | Out-String
Assert-Check "long frame title truncates to W=32" ($LASTEXITCODE -eq 0 -and $longTitleValidate -match '\[PASS\]')

python -c "open(r'$tmpDir\nested-box.txt','w',encoding='utf-8').write('\n'.join(['\u250c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510','\u2502 inner content   \u2502','\u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518','below the box']))" | Out-Null
$nestedFrame = python $helper frame --mode sp --title "Wrap" --file (Join-Path $tmpDir "nested-box.txt") 2>&1 | Out-String
$nestedFrameFile = Join-Path $tmpDir "nested-frame-out.txt"
[System.IO.File]::WriteAllText($nestedFrameFile, $nestedFrame.Trim(), [System.Text.UTF8Encoding]::new($false))
$nestedValidate = python $helper validate --mode sp --file $nestedFrameFile 2>&1 | Out-String
Assert-Check "nested box inside frame validates" ($nestedValidate -match '\[PASS\]' -and $nestedFrame -match '\u2502\u250c')

$inlineOut = python $helper sparkline --mode inline --values "1,2,3" 2>&1 | Out-String
Assert-Check "inline mode supported" ($inlineOut.Trim().Length -ge 3)

# --- pad self-validates each line ---
$padOut = python $helper pad --mode pc --text "hello pad test" 2>&1 | Out-String
Assert-Check "pad output validates" ($padOut -match 'hello pad test' -and $LASTEXITCODE -eq 0)

$sliderPath = Join-Path $tmpDir "slider.txt"
python -c "import subprocess, pathlib; h=r'$helper'; s=subprocess.check_output(['python', h, 'slider', '--val', '50', '--min', '0', '--max', '100', '--width', '40', '--label-left', 'Lo', '--label-right', 'Hi'], text=True); pathlib.Path(r'$sliderPath').write_text(s, encoding='utf-8')"
$sliderValidate = python $helper validate --width 40 --file $sliderPath 2>&1 | Out-String
Assert-Check "slider exact width 40" ($sliderValidate -match '\[PASS\]')

$progOut = python $helper progress --val 7 --max 10 --width 12 2>&1 | Out-String
Assert-Check "progress bar renders" ($progOut -match '\[+' -and $progOut.Trim().Length -eq 12)

Write-Host "`nSummary: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) { exit 1 }
exit 0
