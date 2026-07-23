vim.pack.add({ 'https://github.com/sainnhe/everforest' })

-- Everforest is a classic Vim-style colorscheme configured via vim.g
-- variables that must be set *before* `colorscheme everforest` runs (see
-- :help everforest-configuration). 'medium' is the default contrast level
-- and the same one used elsewhere (WezTerm, tmux); drop to 'soft' here if
-- eye strain is still an issue at 'medium'.
vim.g.everforest_background = 'medium'
vim.g.everforest_better_performance = 1
-- transparent_background=2 clears Normal, NormalFloat, StatusLine, etc.
vim.g.everforest_transparent_background = 2

local function clear_background()
    -- Belt-and-suspenders on top of transparent_background=2: make sure
    -- floats and the completion popup menu stay transparent too.
    vim.api.nvim_set_hl(0, 'Normal', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'Pmenu', { bg = 'NONE' })
end

-- Appearance syncing: reads the shared state file kept up to date by the
-- appearance-watcher LaunchAgent (~/.dotfiles/bin/appearance-watcher.sh),
-- the single source of truth for "is macOS in dark or light mode" shared
-- across sketchybar/tmux/btop/nvim (see AGENTS.md's "Auto dark/light mode
-- syncing" section). A plain file read here is far cheaper than spawning a
-- `defaults read` subprocess on a timer.
local appearance_file = vim.fn.expand('~/.cache/appearance')
local current_appearance = nil

local function apply_appearance(appearance)
    if appearance == current_appearance then return end
    current_appearance = appearance
    vim.o.background = appearance
    vim.cmd.colorscheme('everforest')
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
-- unlike a subprocess-per-check approach.
local timer = vim.uv.new_timer()
timer:start(2000, 2000, vim.schedule_wrap(sync_appearance))

-- Guaranteed correction point: `focus-events on` in tmux.conf (set by the
-- tmux-sensible plugin) means nvim gets FocusGained the moment you switch
-- back to this pane, so a change that happened while unfocused is caught
-- immediately rather than waiting up to 2s for the timer above.
vim.api.nvim_create_autocmd('FocusGained', {
    callback = sync_appearance,
})
