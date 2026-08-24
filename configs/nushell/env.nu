# Nushell Environment Configuration ($nu.env-path)

# Environment variables
$env.EDITOR = "hx"
$env.VISUAL = "hx"
$env.GIT_EDITOR = "hx"
$env.BAT_THEME = "Catppuccin Mocha"
$env.BAT_PAGER = ""
$env.BAT_STYLE = "plain"
$env.PAGER = "cat"
$env.GIT_PAGER = "cat"
$env.DELTA_PAGER = "cat"
$env.PYTHONUTF8 = "1"
$env.POWERSHELL_TELEMETRY_OPTOUT = "1"
$env.DOTNET_CLI_TELEMETRY_OPTOUT = "1"

# Ensure ~/.local/bin is at the front of PATH
let local_bin = ($env.USERPROFILE | path join ".local" "bin")
if ($local_bin | path exists) {
    $env.PATH = ($env.PATH | split row (char esep) | prepend $local_bin)
}

# Starship & Zoxide initialization
let autoload_dir = ($nu.data-dir | path join "vendor/autoload")
if not ($autoload_dir | path exists) {
    mkdir $autoload_dir
}

let starship_nu = ($autoload_dir | path join "starship.nu")
if not ($starship_nu | path exists) {
    if (which starship | is-not-empty) {
        starship init nu | save -f $starship_nu
    }
}

let zoxide_nu = ($autoload_dir | path join "zoxide.nu")
if not ($zoxide_nu | path exists) {
    if (which zoxide | is-not-empty) {
        zoxide init nushell | save -f $zoxide_nu
    }
}
