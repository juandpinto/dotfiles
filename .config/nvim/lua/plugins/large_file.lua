-- Disables expensive features (treesitter, swapfile, undo, wrap, matchparen)
-- for files over a size threshold, so opening large/minified files (big
-- JSON, CSV, logs, etc.) doesn't bog down or hang Neovim.

----------------------------------------------------------------------------
-- User settings -- tweak these
----------------------------------------------------------------------------
local settings = {
    size_limit = 4 * 1024 * 1024, -- files larger than this (in bytes) are considered "large"
    buffer_options = { -- buffer options applied to large files
        swapfile = false, -- disable swapfile
        bufhidden = 'unload', -- unload buffer when hidden
        buftype = 'nowrite', -- prevent accidental :write on a huge buffer
        undolevels = -1, -- disable undo history
    },
    notify = function(ev)
        vim.notify(
            ('Large file detected (%s) — disabled: swapfile, undo, treesitter highlighting, line wrap, matchparen'):format(
                ev.file
            ),
            vim.log.levels.WARN
        )
    end,
}
----------------------------------------------------------------------------

-- Create a new autocommand group for large file optimizations
local group = vim.api.nvim_create_augroup('LargeFileAutocmds', {})
-- Variable to store the previous state of eventignore
local old_eventignore = false

-- Function to handle BufReadPre event
local function buf_read_pre(ev)
    if not ev.file then return end

    local ok, size = pcall(function() return vim.uv.fs_stat(ev.file).size end)
    if not (ok and size and size > settings.size_limit) then return end

    old_eventignore = vim.o.eventignore -- store the current eventignore setting
    vim.b[ev.buf].is_large_file = true -- mark buffer as containing a large file
    vim.o.eventignore = 'FileType' -- ignore FileType events (skips treesitter attach, etc.)
    for option, value in pairs(settings.buffer_options) do
        vim.bo[option] = value
    end
    -- Deferred: if fired synchronously here, Neovim's own "file" info message
    -- (printed once the read finishes) immediately overwrites this on the
    -- command line, so the warning never appears to be shown.
    vim.schedule(function() settings.notify(ev) end)
end

-- Function to handle BufWinEnter event
local function buf_win_enter(ev)
    if old_eventignore ~= false then
        vim.o.eventignore = old_eventignore -- restore the eventignore setting
        old_eventignore = false
    end

    if vim.b[ev.buf].is_large_file then
        -- 'wrap' is a pure window-local option (no distinct global value to
        -- fall back to later), so remember this window's value the first
        -- time, to hand back to LargeFileRestore.
        if vim.b[ev.buf].large_file_prev_wrap == nil then
            vim.b[ev.buf].large_file_prev_wrap = vim.wo.wrap
        end
        vim.wo.wrap = false -- disable line wrapping for large files
    else
        vim.wo.wrap = vim.o.wrap -- restore line wrapping setting
    end
end

-- Function to handle BufEnter event
local function buf_enter(ev)
    if vim.b[ev.buf].is_large_file then
        if vim.g.loaded_matchparen then vim.cmd('NoMatchParen') end
    elseif not vim.g.loaded_matchparen then
        vim.cmd('DoMatchParen')
    end
end

vim.api.nvim_create_autocmd(
    'BufReadPre',
    { group = group, callback = buf_read_pre }
)
vim.api.nvim_create_autocmd(
    'BufWinEnter',
    { group = group, callback = buf_win_enter }
)
vim.api.nvim_create_autocmd('BufEnter', { group = group, callback = buf_enter })

-- Manually re-enable the features disabled above for the current buffer,
-- restoring Neovim's normal global defaults.
vim.api.nvim_create_user_command('LargeFileRestore', function()
    local buf = vim.api.nvim_get_current_buf()
    if not vim.b[buf].is_large_file then
        vim.notify('Not marked as a large file', vim.log.levels.INFO)
        return
    end

    -- Restore buffer-local options to Neovim's global default values
    for option in pairs(settings.buffer_options) do
        vim.bo[option] =
            vim.api.nvim_get_option_value(option, { scope = 'global' })
    end
    vim.wo.wrap = vim.b[buf].large_file_prev_wrap
    if vim.wo.wrap == nil then
        vim.wo.wrap = true -- fallback if we somehow never captured it
    end
    vim.b[buf].large_file_prev_wrap = nil
    -- Clear the marker before the remaining (plugin-dependent) steps below,
    -- so a failure there doesn't leave the buffer stuck mid-restore.
    vim.b[buf].is_large_file = false

    -- Re-run FileType autocmds for this buffer's current filetype, since they
    -- were skipped on load (this is what reattaches treesitter, etc.)
    vim.api.nvim_exec_autocmds('FileType', { buffer = buf, modeline = false })

    -- Re-enable matchparen if it's currently globally disabled
    if not vim.g.loaded_matchparen then vim.cmd('DoMatchParen') end

    vim.notify(
        'Large-file optimizations disabled for this buffer — restored global defaults',
        vim.log.levels.INFO
    )
end, {
    desc = 'Restore normal Neovim features (treesitter, undo, swapfile, wrap, matchparen) disabled for the current large file',
})
