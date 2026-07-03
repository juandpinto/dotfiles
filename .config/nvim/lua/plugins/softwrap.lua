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
-- Only the rightmost window in each horizontal row of the layout is padded
-- (stacked/horizontal splits still each get their own, since they don't
-- block each other horizontally). This keeps side-by-side windows packed
-- against each other with no gaps in between, and puts all spare width in
-- one place: a single pad trailing the outermost right edge. If that
-- window doesn't have enough room to spare, no padding is added and it
-- just wraps at its own real edge, same as if this module weren't here.
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

-- Returns a set of the real (non-pad) windows in the current tabpage that
-- have nothing else to their right -- the only ones that should get a
-- pad. `vim.fn.winlayout()` describes the window tree as nested
-- {'row', children} (side-by-side, i.e. vsplits) and {'col', children}
-- (stacked, i.e. splits) nodes down to {'leaf', winid} windows. Within a
-- 'row', only the last child has nothing to its right, so only it is
-- recursed into (skipping over a trailing pad leaf first, since a
-- window's own pad doesn't block *it* from being rightmost). Within a
-- 'col', every child is equally exposed on the right (they're only
-- stacked vertically), so all of them are recursed into.
local function rightmost_real_wins()
    local rightmost = {}

    local function visit(node)
        local kind = node[1]
        if kind == 'leaf' then
            local win = node[2]
            if not is_pad_win(win) then rightmost[win] = true end
        elseif kind == 'row' then
            local children = node[2]
            for i = #children, 1, -1 do
                local child = children[i]
                local is_trailing_pad = child[1] == 'leaf'
                    and is_pad_win(child[2])
                if not is_trailing_pad then
                    visit(child)
                    break
                end
            end
        elseif kind == 'col' then
            for _, child in ipairs(node[2]) do
                visit(child)
            end
        end
    end

    visit(vim.fn.winlayout())
    return rightmost
end

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

-- True when `win` looks like Nvim's own startup state: launched with no
-- file arguments, still showing the single empty unnamed scratch buffer.
-- Nvim only draws its built-in ":intro" splash screen when exactly one
-- window/buffer exists at startup; opening a pad window here -- even
-- momentarily -- forces a full redraw that permanently suppresses it (Nvim
-- checks window/buffer count once, early in startup, not continuously).
-- Skipping padding for this exact case lets the splash show as normal; the
-- check re-evaluates on every refresh, so padding resumes the moment the
-- user actually starts editing (buffer becomes modified, a file is opened,
-- another window is created, etc).
local function is_startup_screen(win)
    if vim.fn.argc() ~= 0 then return false end
    if #vim.api.nvim_list_tabpages() > 1 then return false end
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then return false end

    local buf = vim.api.nvim_win_get_buf(win)
    return vim.fn.bufname(buf) == ''
        and not vim.bo[buf].modified
        and vim.api.nvim_buf_line_count(buf) <= 1
        and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ''
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
        and not is_startup_screen(win)
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

    local rightmost = rightmost_real_wins()

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(win) and not is_pad_win(win) then
            local pad = pad_for[win]
            local pad_valid = pad and vim.api.nvim_win_is_valid(pad)

            -- This window's "natural" width, i.e. what it would be with no
            -- pad at all. A pad also carves out one extra column for the
            -- divider between it and `win`, so recovering the natural width
            -- from a padded window means adding that column back too, on
            -- top of the pad's own width -- not just the pad's width alone.
            local natural_width = vim.api.nvim_win_get_width(win)
            if pad_valid then
                natural_width = natural_width
                    + 1
                    + vim.api.nvim_win_get_width(pad)
            end

            local extra = (is_eligible(win) and rightmost[win])
                    and (natural_width - settings.width - text_offset(win))
                or -1

            if extra > settings.min_pad then
                -- The pad itself will cost `win` one more column for the
                -- divider between them, on top of the pad's width, so ask
                -- for one column less than `extra` here to land `win`
                -- exactly on `settings.width` once that divider is
                -- accounted for.
                local target_pad_width = extra - 1
                if pad_valid then
                    if vim.api.nvim_win_get_width(pad) ~= target_pad_width then
                        vim.api.nvim_win_set_width(pad, target_pad_width)
                    end
                else
                    pad_for[win] = open_pad(win, target_pad_width)
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
