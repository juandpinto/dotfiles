vim.pack.add({ 'https://github.com/catppuccin/nvim' })

local function clear_background()
    -- Transparent background (override catppuccin's solid floats too)
    vim.api.nvim_set_hl(0, 'Normal', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'Pmenu', { bg = 'NONE' })
end

require('catppuccin').setup({
    -- "auto" reads vim.o.background: "dark" → mocha, "light" → latte
    flavour = 'auto',
    background = {
        light = 'latte',
        dark = 'mocha',
    },
    transparent_background = true,
    default_integrations = true,
    integrations = {
        treesitter = true,
        gitsigns = true,
        which_key = true,
        blink_cmp = true,
        mini = { enabled = true },
        neo_tree = true,
        telescope = { enabled = true },
    },
})

-- Appearance syncing: reads the shared state file kept up to date by the
-- appearance-watcher LaunchAgent (~/.dotfiles/bin/appearance-watcher.sh),
-- the single source of truth for "is macOS in dark or light mode" shared
-- across sketchybar/tmux/btop/nvim (see AGENTS.md's "Auto dark/light mode
-- syncing" section). This replaced auto-dark-mode.nvim, which polled its own
-- `defaults read -g AppleInterfaceStyle` subprocess every second -- a plain
-- file read here is far cheaper and avoids yet another independent poller.
local appearance_file = vim.fn.expand('~/.cache/appearance')
local current_appearance = nil

local function apply_appearance(appearance)
    if appearance == current_appearance then return end
    current_appearance = appearance
    vim.o.background = appearance
    vim.cmd.colorscheme('catppuccin')
    clear_background()
end

local function sync_appearance()
    local file = io.open(appearance_file, 'r')
    if not file then return end
    local contents = file:read('*l')
    file:close()
    if contents == 'dark' or contents == 'light' then
        apply_appearance(contents)
    end
end

sync_appearance() -- pick up current appearance immediately on startup

-- Background safety net: cheap enough (just a file read) to poll directly,
-- unlike the old subprocess-per-check approach.
local timer = vim.uv.new_timer()
timer:start(2000, 2000, vim.schedule_wrap(sync_appearance))

-- Guaranteed correction point: `focus-events on` in tmux.conf (set by the
-- tmux-sensible plugin) means nvim gets FocusGained the moment you switch
-- back to this pane, so a change that happened while unfocused is caught
-- immediately rather than waiting up to 2s for the timer above.
vim.api.nvim_create_autocmd('FocusGained', {
    callback = sync_appearance,
})
