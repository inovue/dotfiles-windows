# PowerShell Profile for Windows (PowerShell 7 & Windows PowerShell 5.1)
# dotfiles-windows: Optimized for Speed, Stability & AI Agent Non-Interactive Execution

# --- 1. UTF-8 Output & Console Encoding ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# --- 2. Remove Slow & Conflicting Built-in Cmdlet Aliases ---
# Prevents 'cat', 'ls', 'curl', etc. from executing slow .NET cmdlets instead of fast native executables.
$aliasesToRemove = @("cat", "ls", "curl", "wget", "sc", "gc", "cp", "rm", "mv", "sort")
foreach ($alias in $aliasesToRemove) {
    if (Get-Alias -Name $alias -ErrorAction SilentlyContinue) {
        Remove-Item "Alias:$alias" -Force -ErrorAction SilentlyContinue
    }
}

# --- 3. Default Environment Variables (Pagers & Non-Interactive Safety) ---
$env:PAGER                     = "cat"
$env:BAT_PAGER                 = ""
$env:BAT_STYLE                 = "plain"
$env:GIT_PAGER                 = "cat"
$env:DELTA_PAGER               = "cat"
$env:PYTHONUTF8                = "1"
$env:POWERSHELL_TELEMETRY_OPTOUT = "1"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"

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
    Invoke-Expression (&starship init powershell)
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (&zoxide init powershell)
}
