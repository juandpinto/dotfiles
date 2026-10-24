-- Small native quality-of-life behaviors; no plugin/framework dependency.
local group = vim.api.nvim_create_augroup('juan-native-qol', { clear = true })

vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave' }, {
    group = group,
    desc = 'Check for externally changed files when returning to the editor',
    callback = function()
        if vim.bo.buftype == '' and vim.fn.getcmdwintype() == '' then
            vim.cmd.checktime()
        end
    end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    desc = 'Restore the last cursor location in ordinary files',
    callback = function(event)
        local buf = event.buf
        if vim.bo[buf].buftype ~= '' or vim.b[buf].juan_last_location then
            return
        end
        if
            vim.tbl_contains({ 'gitcommit', 'gitrebase' }, vim.bo[buf].filetype)
        then
            return
        end
        vim.b[buf].juan_last_location = true
        local mark = vim.api.nvim_buf_get_mark(buf, '"')
        if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(buf) then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
    end,
})

vim.api.nvim_create_autocmd('FileType', {
    group = group,
    desc = 'Close help and diagnostic utility windows with q',
    pattern = {
        'help',
        'qf',
        'checkhealth',
        'lspinfo',
        'gitsigns-blame',
        'startuptime',
        'notify',
    },
    callback = function(event)
        vim.bo[event.buf].buflisted = false
        vim.keymap.set('n', 'q', '<cmd>close<CR>', {
            buffer = event.buf,
            silent = true,
            desc = 'Close utility window',
        })
    end,
})
