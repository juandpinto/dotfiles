-- Personal overrides; Omarchy's packaged defaults remain untouched.
local active_border = 'rgba(e67e80ff)' -- Same Everforest red as Mac JankyBorders.
local inactive_border = 'rgba(56635f00)'

hl.config({
    general = {
        col = {
            active_border = active_border,
            inactive_border = inactive_border,
        },
        gaps_in = 3, -- Between tiled windows
        gaps_out = {
            top = 3, -- Between windows and the bar's reserved area
            right = 8, -- Between windows and the screen's right edge
            bottom = 8, -- Between windows and the screen's bottom edge
            left = 8, -- Between windows and the screen's left edge
        },
    },
    scrolling = {
        -- See only one column per screen instead of two.
        column_width = 0.97,
    },
    group = {
        col = {
            border_active = active_border,
            border_inactive = inactive_border,
            border_locked_active = active_border,
            border_locked_inactive = inactive_border,
        },
    },
    decoration = {
        rounding = 8,
        dim_inactive = true,
        dim_strength = 0.15,
        blur = {
            enabled = true,
            size = 4,
            passes = 2,
        },
    },
})

-- Frost only the bar's translucent background, using the existing gentle blur.
-- Ignore fully transparent pixels when Omarchy's background toggle is used.
hl.layer_rule({
    match = { namespace = '^omarchy-bar$' },
    blur = true,
    ignore_alpha = 0.2,
})

-- Hyprland reevaluates this native selector when workspace window counts change.
-- Invisible inactive borders keep multi-window geometry stable when focus moves.
o.window({ workspace = 'w[1]' }, { border_size = 0 })

-- Keep the prior no-blur behavior for other apps. Kitty asks for blur; Hyprland
-- controls its strength. The Herdr launcher uses its own terminal app-id.
o.window('.*', { no_blur = true })
o.window('^(kitty|org\\.omarchy\\.herdr)$', { no_blur = false })

-- Match Kitty's background blur, but keep fullscreen Brave content opaque.
-- Web apps get a derived class (brave-<host>__<path>-Default), so list them.
o.window('^brave-(origin|music\\.apple\\.com__-Default|app\\.todoist\\.com__-Default)$', {
    opacity = '0.93 override 0.93 override 1.0 override',
    no_blur = false,
})
