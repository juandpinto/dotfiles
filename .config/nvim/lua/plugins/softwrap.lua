-- Soft-wraps text at a fixed column (like VSCode's "bounded" word wrap)
-- even in a wide terminal, without the cost/fragility of plugins that
-- compute wrap points by scanning buffer content (e.g. rickhowe/wrapwidth,
-- which hangs on very long single-line files via virtcol()).
--
-- How: pad the right side of each normal editing window with a fixed-width
-- empty scratch window so the *real* window is narrower, then let Neovim's
-- native 'wrap'/'linebreak' (see options.lua) wrap at that real edge. This
-- only ever does arithmetic on window widths -- it never reads buffer
-- content, so it's robust regardless of file size or line length.
--
-- Applies independently to every eligible window (sidebar + single editor,
-- side-by-side splits, stacked splits, etc.). If a window doesn't have
-- enough room to spare, no padding is added and it just wraps at its own
-- real edge, same as if this module weren't here.
--
-- Pad widths are only changed when they actually need to (vs. unconditional
-- close+recreate on every refresh), which keeps this idempotent: opening or
-- resizing a pad fires more Win* events, so without this check the module
-- would re-trigger itself forever.

----------------------------------------------------------------------------
-- User settings -- tweak these
----------------------------------------------------------------------------
local settings = {
    width = 80, -- desired text width
    min_pad = 4, -- only pad if there's at least this much room to spare
}
----------------------------------------------------------------------------

-- Maps a real window id -> the pad window id padding it (if any).
local pad_for = {}

local function is_pad_win(win) return vim.w[win].softwrap_pad == true end

-- Columns eaten by 'number'/'relativenumber', 'signcolumn', and 'foldcolumn'
-- in front of the actual text. nvim_win_get_width() includes these, but we
-- want `settings.width` columns of *text*, so this must be added back on
-- top of the target. Computed live (rather than reimplementing the
-- numberwidth/signcolumn/foldcolumn math) so it stays correct even as it
-- changes dynamically (e.g. numberwidth growing with line count).
local function text_offset(win)
    local info = vim.fn.getwininfo(win)[1]
    return info and info.textoff or 0
end

local function is_eligible(win)
    local buf = vim.api.nvim_win_get_buf(win)
    -- Padding only makes sense if the window will actually wrap; if the user
    -- manually turned 'wrap' off (e.g. `:set wrap!`), a pad would just hide
    -- content off-screen for no benefit, so respect that and give the window
    -- back its full width.
    return vim.bo[buf].buftype == ''
        and not vim.b[buf].is_large_file
        and vim.wo[win].wrap
end

local function close_pad(win)
    if not vim.api.nvim_win_is_valid(win) then return end
    -- Use ':quit' semantics rather than nvim_win_close/':close': if this pad
    -- ends up being the last window (e.g. the user just quit their only real
    -- buffer), ':close' refuses ("E444: cannot close last window"), leaving
    -- the empty pad on screen instead of Neovim exiting like it normally
    -- would. ':quit' falls through correctly in every case: closes just this
    -- window when others exist, closes the tab when it's the last window of
    -- a multi-tab session, or quits Neovim when it's the very last window.
    pcall(vim.api.nvim_win_call, win, function() vim.cmd('quit!') end)
end

local function open_pad(anchor_win, width)
    local ok, win = pcall(
        vim.api.nvim_open_win,
        vim.api.nvim_create_buf(false, true),
        false,
        {
            win = anchor_win,
            split = 'right',
            width = width,
        }
    )
    if not ok then return nil end

    vim.w[win].softwrap_pad = true
    vim.bo[vim.api.nvim_win_get_buf(win)].swapfile = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].foldcolumn = '0'
    vim.wo[win].cursorline = false
    vim.wo[win].winfixwidth = true
    return win
end

local refreshing = false

local function refresh()
    if refreshing then return end
    refreshing = true

    local original_win = vim.api.nvim_get_current_win()

    -- Drop bookkeeping for windows that no longer exist, closing their pad.
    for win, pad in pairs(pad_for) do
        if not vim.api.nvim_win_is_valid(win) then
            close_pad(pad)
            pad_for[win] = nil
        end
    end

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(win) and not is_pad_win(win) then
            local pad = pad_for[win]
            local pad_valid = pad and vim.api.nvim_win_is_valid(pad)

            -- This window's "natural" width, ignoring any pad it already has.
            local natural_width = vim.api.nvim_win_get_width(win)
            if pad_valid then
                natural_width = natural_width + vim.api.nvim_win_get_width(pad)
            end

            local extra = is_eligible(win)
                    and (natural_width - settings.width - text_offset(win))
                or -1

            if extra > settings.min_pad then
                if pad_valid then
                    if vim.api.nvim_win_get_width(pad) ~= extra then
                        vim.api.nvim_win_set_width(pad, extra)
                    end
                else
                    pad_for[win] = open_pad(win, extra)
                end
            elseif pad_valid then
                close_pad(pad)
                pad_for[win] = nil
            end
        end
    end

    if vim.api.nvim_win_is_valid(original_win) then
        vim.api.nvim_set_current_win(original_win)
    end
    refreshing = false
end

local group = vim.api.nvim_create_augroup('SoftWrap', {})

-- Pad windows aren't meant to be a real destination (e.g. `:only` while
-- focused in one would wipe out the actual editing window). Bounce back to
-- the previously focused window immediately if one is ever entered.
vim.api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function()
        if
            is_pad_win(vim.api.nvim_get_current_win())
            and vim.fn.winnr('$') > 1
        then
            vim.cmd('wincmd p')
        end
    end,
})

vim.api.nvim_create_autocmd(
    { 'WinEnter', 'BufWinEnter', 'WinClosed', 'WinResized', 'VimResized' },
    {
        group = group,
        callback = function() vim.schedule(refresh) end,
    }
)

-- Also refresh whenever 'wrap' itself is toggled (e.g. `:set wrap!`), so
-- turning wrap off drops the pad immediately, and turning it back on
-- restores it.
vim.api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = 'wrap',
    callback = function() vim.schedule(refresh) end,
})
