-- WezTerm Configuration
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Font configuration (HackGen Console NF for Japanese + Nerd Fonts)
config.font = wezterm.font_with_fallback({
  'HackGen Console NF',
  'JetBrainsMono Nerd Font',
  'Segoe UI Emoji',
})
config.font_size = 11.5
config.line_height = 1.1

-- Appearance & Colors
config.color_scheme = 'Catppuccin Mocha'
config.window_background_opacity = 0.95
config.win32_system_backdrop = 'Acrylic'

config.window_padding = {
  left = 12,
  right = 12,
  top = 8,
  bottom = 8,
}

-- Tab bar style
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = false

-- Default shell to Nushell if available, fallback to pwsh / powershell
local nu_path = 'nu.exe'
config.default_prog = { nu_path }

-- Window decorations
config.window_decorations = "RESIZE"

-- Cursor style
config.default_cursor_style = 'BlinkingBar'
config.animation_fps = 60
config.cursor_blink_rate = 650

return config
