# PowerShell Profile for Windows (PowerShell 7 & Windows PowerShell 5.1)
# dotfiles-windows: Optimized for Speed, Stability & AI Agent Non-Interactive Execution

# --- 1. UTF-8 Output & Console Encoding ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# --- 2. Remove Slow & Conflicting Built-in Cmdlet Aliases ---
# Prevents 'cat', 'ls', 'curl', etc. from executing slow .NET cmdlets instead of fast native executables.
$aliasesToRemove = @("cat", "ls", "curl", "wget", "sc", "gc", "cp", "rm", "mv", "sort", "diff", "ps", "kill", "tee", "sleep", "man")
foreach ($alias in $aliasesToRemove) {
    if (Get-Alias -Name $alias -ErrorAction SilentlyContinue) {
        Remove-Item "Alias:$alias" -Force -ErrorAction SilentlyContinue
    }
}

# --- 3. Default Environment Variables (Pagers, Non-Interactive Safety & AI Key Bridge) ---
$env:PAGER                       = "cat"
$env:BAT_PAGER                   = ""
$env:BAT_STYLE                   = "plain"
$env:GIT_PAGER                   = "cat"
$env:DELTA_PAGER                 = "cat"
$env:PYTHONUTF8                  = "1"
$env:POWERSHELL_TELEMETRY_OPTOUT = "1"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"

# Bridge User Registry AI/LLM keys if missing in process table (transparent subshell resolution)
$aiKeys = @("OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_MODEL", "GEMINI_API_KEY", "GOOGLE_API_KEY", "ANTHROPIC_API_KEY", "DEEPSEEK_API_KEY", "KIMI_API_KEY", "MOONSHOT_API_KEY")
foreach ($k in $aiKeys) {
    if (-not [System.Environment]::GetEnvironmentVariable($k, "Process")) {
        $v = [System.Environment]::GetEnvironmentVariable($k, "User")
        if ($v) { [System.Environment]::SetEnvironmentVariable($k, $v, "Process") }
    }
}

# Ensure ~/.local/bin is in PATH for fnm, modern CLI tools, and runtime shims
$localBin = Join-Path $env:USERPROFILE ".local\bin"
if ((Test-Path $localBin) -and ($env:Path -notlike "*$localBin*")) {
    $env:Path = "$localBin;$env:Path"
}

# Initialize fnm (Fast Node Manager) for Node.js / npm / pnpm resolution
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

# --- 4. Fast Non-Interactive Guard for AI Agents & Automation ---
# Subprocesses spawned by Antigravity, Cursor, Claude Code, etc. return immediately here.
$isNonInteractive = $false
try {
    if (-not [Environment]::UserInteractive -or $env:TERM_PROGRAM -eq "antigravity" -or $env:CI -eq "1" -or [Console]::IsInputRedirected) {
        $isNonInteractive = $true
    }
} catch {
    $isNonInteractive = $true
}
if ($isNonInteractive) {
    return
}

# --- 5. Interactive Session Enhancements (Human Terminal Use Only) ---
# If Starship / Zoxide are installed, initialize them for interactive PowerShell
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell --print-full-init | Out-String)
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (&zoxide init powershell | Out-String)
}
