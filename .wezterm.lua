local wezterm = require("wezterm")
local config = wezterm.config_builder()

local themes = {
  -- dark  = { scheme = "Dracula+",        background = "#111111" },
  -- dark  = { scheme = "Catppuccin Mocha", background = "#111111" },
  -- dark  = { scheme = "Catppuccin Mocha" },
  -- dark  = { scheme = "Gruvbox Material", background = "#111111" },
  -- dark  = { scheme = "Gruvbox Dark (Gogh)", background = "#111111" },
  dark = { scheme = "Vs Code Dark+ (Gogh)" },
  -- dark  = { scheme = "Gruvbox Dark (Gogh)" },
  -- light = { scheme = "Catppuccin Latte", background = "#eff1f5" },
  -- light = { scheme = "Gruvbox (Gogh)", background = "#ffffee" },
  light = { scheme = "Vs Code Light+ (Gogh)" },
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
config.font_size = 14
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.95
config.macos_window_background_blur = 10

-- Keymaps
-- config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 2000 }
--
-- local action = wezterm.action
-- config.keys = {
--     {
--         key = '"',
--         mods = "LEADER",
--         action = action.SplitVertical({ domain = "CurrentPaneDomain" }),
--     },
--
--     {
--         key = "%",
--         mods = "LEADER",
--         action = action.SplitHorizontal({ domain = "CurrentPaneDomain" }),
--     },
-- }
--

config.enable_tab_bar = false
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = false
config.tab_max_width = 25

-- Display Workspace name on the left and date/time on the right
-- wezterm.on('update-status', function(window, pane)
--   local workspace = window:active_workspace()
--   local date = wezterm.strftime('%H:%M')
--   -- local date = wezterm.strftime(" %I:%M %p  %A  %B %-d ");
--   -- local cwd = pane:get_current_working_dir()--:sub(8); -- remove file:// uri prefix
--   local hostname = " "..wezterm.hostname().." ";
--   window:set_left_status(' ' .. workspace .. ' ')
--   -- window:set_right_status(' ' .. cwd .. ' ' .. date .. ' ')
-- end)
--
-- wezterm.on("update-status", function(window, pane)
--   local cwd = " "..pane:get_current_working_dir():sub(8).." "; -- remove file:// uri prefix
--   local date = wezterm.strftime(" %I:%M %p  %A  %B %-d ");
--   local hostname = " "..wezterm.hostname().." ";
--
--   window:set_right_status(
--     wezterm.format({
--       {Foreground={Color="#ffffff"}},
--       {Background={Color="#005f5f"}},
--       {Text=cwd},
--       {Foreground={Color="#00875f"}},
--       {Background={Color="#005f5f"}},
--       {Text=""},
--       {Foreground={Color="#ffffff"}},
--       {Background={Color="#00875f"}},
--       {Text=date},
--       {Foreground={Color="#00af87"}},
--       {Background={Color="#00875f"}},
--       {Text=""},
--       {Foreground={Color="#ffffff"}},
--       {Background={Color="#00af87"}},
--       {Text=hostname},
--     })
--   )
-- end)
--

-- wezterm.plugin
--   .require('https://github.com/yriveiro/wezterm-status')
--   .apply_to_config(config)
--
-- wezterm.plugin
--   .require('https://github.com/yriveiro/wezterm-status')
--   .apply_to_config(config, {
--     cells = {
--       battery = { enabled = false },
--       date = { enabled = false, format = '%H:%M' },
--       mode = { enabled = true },
--       workspace = { enabled = true }
--     }
--   })
--

local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")

tabline.setup({
  options = {
    icons_enabled = true,
    theme = 'Vs Code Dark+ (Gogh)',
    -- theme = 'Gruvbox Dark (Gogh)',
    tabs_enabled = true,
    theme_overrides = {},
    section_separators = {
      left = wezterm.nerdfonts.pl_left_hard_divider,
      right = wezterm.nerdfonts.pl_right_hard_divider,
    },
    component_separators = {
      left = wezterm.nerdfonts.pl_left_soft_divider,
      right = wezterm.nerdfonts.pl_right_soft_divider,
    },
    tab_separators = {
      left = wezterm.nerdfonts.pl_left_hard_divider,
      right = wezterm.nerdfonts.pl_right_hard_divider,
    },
  },
  sections = {
    tabline_a = { 'mode' },
    tabline_b = { 'workspace' },
    tabline_c = { ' ' },
    tab_active = {
      'index',
      { 'parent', padding = 0 },
      '/',
      { 'cwd', padding = { left = 0, right = 1 } },
      { 'zoomed', padding = 0 },
    },
    tab_inactive = { 'index', { 'process', padding = { left = 0, right = 1 } } },
    -- tabline_x = { 'ram', 'cpu' },
    -- tabline_y = { 'datetime', 'battery' },
    -- tabline_z = { 'domain' },
    tabline_y = { },
    tabline_z = { },
    tabline_x = { 'ram', 'cpu' },
  },
  extensions = {},
})

config.window_padding = {
  left = 10,
  right = 10,
  top = 5,
  bottom = 2,
}

return config
