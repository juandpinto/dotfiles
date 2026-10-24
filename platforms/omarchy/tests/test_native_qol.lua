-- Run with: nvim --headless -u NONE -l platforms/omarchy/tests/test_native_qol.lua
vim.opt.rtp:prepend(vim.fn.expand('~/.dotfiles/.config/nvim'))
require('juan.autocmds')
local function eq(expected, actual)
    assert(
        vim.deep_equal(expected, actual),
        vim.inspect({ expected = expected, actual = actual })
    )
end

-- Restore a valid last position; ignore out-of-range marks and commit buffers.
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first', 'second', 'third' })
vim.api.nvim_buf_set_mark(buf, '"', 3, 1, {})
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })
eq({ 3, 1 }, vim.api.nvim_win_get_cursor(0))
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })
eq({ 1, 0 }, vim.api.nvim_win_get_cursor(0)) -- only once per buffer
vim.b[buf].juan_last_location = nil
vim.bo[buf].filetype = 'gitcommit'
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })
eq({ 1, 0 }, vim.api.nvim_win_get_cursor(0))
vim.bo[buf].filetype = ''
vim.b[buf].juan_last_location = nil
local get_mark = vim.api.nvim_buf_get_mark
vim.api.nvim_buf_get_mark = function() return { 99, 0 } end
vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })
vim.api.nvim_buf_get_mark = get_mark
eq({ 1, 0 }, vim.api.nvim_win_get_cursor(0))

-- The focus handler delegates to native checktime only for ordinary files.
-- Actual asynchronous file reload is also tested in an idle editor via RPC.
vim.cmd('enew!')
local checktime = vim.cmd.checktime
local checks = 0
vim.cmd.checktime = function() checks = checks + 1 end
vim.api.nvim_exec_autocmds('FocusGained', {})
eq(1, checks)
vim.bo.buftype = 'nofile'
vim.api.nvim_exec_autocmds('FocusGained', {})
eq(1, checks)
vim.bo.buftype = ''
vim.cmd.checktime = checktime

-- q is buffer-local to utility windows, not ordinary editing buffers.
vim.cmd.enew()
local ordinary = vim.api.nvim_get_current_buf()
eq({}, vim.fn.maparg('q', 'n', false, true))
vim.cmd.new()
vim.bo.filetype = 'help'
local mapping = vim.fn.maparg('q', 'n', false, true)
eq(1, mapping.buffer)
assert(mapping.rhs:lower():find('close'))
eq(false, vim.bo.buflisted)
vim.cmd('normal q')
eq(ordinary, vim.api.nvim_get_current_buf())

-- Re-sourcing replaces the augroup rather than duplicating handlers.
local count = #vim.api.nvim_get_autocmds({ group = 'juan-native-qol' })
package.loaded['juan.autocmds'] = nil
require('juan.autocmds')
eq(count, #vim.api.nvim_get_autocmds({ group = 'juan-native-qol' }))
print('Native autocmd behavior checks passed')
vim.cmd('qa!')
