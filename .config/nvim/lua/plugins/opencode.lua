vim.pack.add({
    {
        src = 'https://github.com/nickjvandyke/opencode.nvim',
        version = vim.version.range('*'), -- Latest stable release
    },
})

vim.o.autoread = true -- Required for `vim.g.opencode_opts.events.reload`

-- ---------------------------------------------------------------------------
-- Tmux pane management
--
-- opencode runs in a 35%-wide right pane via `opencode --port` (required so
-- the plugin can connect to it over HTTP).  Toggle hides/shows the pane with
-- `break-pane`/`join-pane` so the opencode session is never lost.
-- Falls back to the plugin default (term://opencode --port) when not in tmux.
-- ---------------------------------------------------------------------------

local pane_id = nil -- tmux pane ID of the opencode pane, e.g. "%3"
local visible = false -- whether the pane is currently shown in this window

local function in_tmux()
    return vim.env.TMUX ~= nil and vim.fn.executable('tmux') == 1
end

-- Returns true when the tracked pane still exists (even if hidden).
local function pane_alive()
    if not pane_id then return false end
    vim.fn.system('tmux display-message -p -t ' .. pane_id .. ' 2>/dev/null')
    if vim.v.shell_error ~= 0 then
        pane_id = nil
        visible = false
        return false
    end
    return true
end

local function tmux_start()
    if pane_alive() and visible then return end

    if pane_alive() then
        -- Pane exists but is hidden in a background window — bring it back.
        vim.fn.system('tmux join-pane -h -l 35% -s ' .. pane_id)
    else
        -- Spawn a fresh pane running `opencode --port` and capture its ID.
        local result = vim.fn.system(
            "tmux split-window -h -l 35% -d -P -F '#{pane_id}' 'opencode --port'"
        )
        pane_id = vim.trim(result)
        -- Disable allow-passthrough to prevent OSC escape codes leaking into
        -- the Neovim buffer while opencode is starting up.
        if pane_id ~= '' then
            vim.fn.system(
                'tmux set-option -t ' .. pane_id .. ' -p allow-passthrough off'
            )
        end
    end
    visible = true
end

local function tmux_stop()
    if not pane_alive() then return end
    vim.fn.system('tmux send-keys -t ' .. pane_id .. ' C-c')
    vim.defer_fn(function()
        if pane_alive() then vim.fn.system('tmux kill-pane -t ' .. pane_id) end
        pane_id = nil
        visible = false
    end, 500)
end

local function tmux_toggle()
    if not pane_alive() then
        tmux_start()
    elseif visible then
        -- Move the pane to a background window without killing opencode.
        vim.fn.system('tmux break-pane -d -s ' .. pane_id)
        visible = false
    else
        -- Restore the hidden pane into the current window.
        vim.fn.system('tmux join-pane -h -l 35% -s ' .. pane_id)
        visible = true
    end
end

-- Kill the pane when Neovim exits so we don't leave orphaned opencode processes.
vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
        if pane_alive() then vim.fn.system('tmux kill-pane -t ' .. pane_id) end
    end,
})

-- ---------------------------------------------------------------------------
-- Plugin options
-- ---------------------------------------------------------------------------

---@type opencode.Opts
vim.g.opencode_opts = {
    server = in_tmux() and {
        start = tmux_start,
        stop = tmux_stop,
        toggle = tmux_toggle,
    } or nil, -- nil → plugin default: term://opencode --port (nvim terminal)

    -- Re-add @diff context removed in v0.13.0.
    contexts = {
        ['@diff'] = function()
            return vim.system({ 'git', '--no-pager', 'diff' }, { text = true })
                :wait().stdout
        end,
    },
}

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

-- Toggle: tmux pane when in tmux, no-op otherwise (nvim terminal has no toggle).
vim.keymap.set('n', '<leader>ot', function()
    if in_tmux() then tmux_toggle() end
end, { desc = 'Toggle OpenCode pane' })

vim.keymap.set(
    { 'n', 'x' },
    '<leader>oa',
    function() require('opencode').ask('@this: ') end,
    { desc = 'Ask OpenCode…' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>os',
    function() require('opencode').select() end,
    { desc = 'Select OpenCode…' }
)

-- Send specific contexts directly without going through ask().
vim.keymap.set(
    { 'n', 'x' },
    '<leader>ob',
    function() require('opencode').prompt('@buffer ') end,
    { desc = 'Send buffer to OpenCode' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>oB',
    function() require('opencode').prompt('@buffers ') end,
    { desc = 'Send all buffers to OpenCode' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>od',
    function() require('opencode').prompt('@diagnostics ') end,
    { desc = 'Send diagnostics to OpenCode' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>oq',
    function() require('opencode').prompt('@quickfix ') end,
    { desc = 'Send quickfix to OpenCode' }
)

vim.keymap.set(
    { 'n', 'x' },
    'go',
    function() return require('opencode').operator('@this ') end,
    { desc = 'Append range to OpenCode', expr = true }
)
vim.keymap.set(
    'n',
    'goo',
    function() return require('opencode').operator('@this ') .. '_' end,
    { desc = 'Append line to OpenCode', expr = true }
)

vim.keymap.set(
    'n',
    '<S-C-u>',
    function() require('opencode').command('session.half.page.up') end,
    { desc = 'Scroll OpenCode up' }
)
vim.keymap.set(
    'n',
    '<S-C-d>',
    function() require('opencode').command('session.half.page.down') end,
    { desc = 'Scroll OpenCode down' }
)
vim.keymap.set(
    'n',
    '<leader>ox',
    function() require('opencode').command('session.interrupt') end,
    { desc = 'Interrupt OpenCode' }
)
vim.keymap.set(
    'n',
    '<leader>on',
    function() require('opencode').command('agent.cycle') end,
    { desc = 'Cycle OpenCode agent' }
)
