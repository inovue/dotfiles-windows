# Nushell Environment Configuration ($nu.env-path)

# Starship & Zoxide initialization
mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
zoxide init nushell | save -f ($nu.data-dir | path join "vendor/autoload/zoxide.nu")

# Environment variables
$env.EDITOR = "hx"
$env.VISUAL = "hx"
$env.GIT_EDITOR = "hx"
$env.BAT_THEME = "Catppuccin Mocha"
