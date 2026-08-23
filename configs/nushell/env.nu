# Nushell Environment Configuration ($nu.env-path)

# Environment variables
$env.EDITOR = "hx"
$env.VISUAL = "hx"
$env.GIT_EDITOR = "hx"
$env.BAT_THEME = "Catppuccin Mocha"

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
