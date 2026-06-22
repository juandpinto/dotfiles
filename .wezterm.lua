local wezterm = require("wezterm")
local config = wezterm.config_builder()

local themes = {
  -- dark  = { scheme = "Dracula+",        background = "#111111" },
  -- dark  = { scheme = "Catppuccin Mocha", background = "#111111" },
  -- dark  = { scheme = "Gruvbox Material", background = "#111111" },
  dark  = { scheme = "Gruvbox Dark (Gogh)", background = "#111111" },
  -- light = { scheme = "Catppuccin Latte", background = "#eff1f5" },
  light = { scheme = "Gruvbox (Gogh)", background = "#ffffff" },
}

local function theme_for_appearance(appearance)
  return appearance:find("Dark") and themes.dark or themes.light
end

local function apply_theme(overrides, appearance)
  local theme = theme_for_appearance(appearance)
  overrides.color_scheme = theme.scheme
  overrides.colors = { background = theme.background }
  return overrides
end

-- Set correct scheme immediately on startup / new windows
if wezterm.gui then
  apply_theme(config, wezterm.gui.get_appearance())
end

-- React to OS appearance changes at runtime
wezterm.on("window-config-reloaded", function(window)
  local overrides = apply_theme(window:get_config_overrides() or {}, window:get_appearance())
  window:set_config_overrides(overrides)
end)

config.font = wezterm.font("MesloLGS Nerd Font Mono")
config.font_size = 13
config.enable_tab_bar = false
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.80
config.macos_window_background_blur = 0

return config
