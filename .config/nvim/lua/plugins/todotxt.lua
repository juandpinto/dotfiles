local todotxt_path = vim.env.HOME .. '/Documents/MH/notes/todo.txt'
local donetxt_path = vim.env.HOME .. '/Documents/MH/notes/done.txt'

-- Only enable this plugin on machines where the todo.txt file actually
-- exists (e.g. skip it on machines without the MH notes directory).
if vim.fn.filereadable(todotxt_path) == 0 then return end

vim.pack.add({ 'https://github.com/phrmendes/todotxt.nvim' })

vim.filetype.add({
    filename = {
        ['todo.txt'] = 'todotxt',
        ['done.txt'] = 'todotxt',
    },
})

require('todotxt').setup({
    todotxt = todotxt_path,
    donetxt = donetxt_path,
    max_priority = 'C',
    metadata = {
        tag = { sort = 'asc' },
        due = { sort = 'asc' },
    },
    ghost_text = {
        enable = true,
        mappings = {
            ['(A)'] = 'today',
            ['(B)'] = 'tomorrow',
            ['(C)'] = 'this week',
        },
    },
})

-- Workaround for upstream bug: LSP code action calls `move_done`,
-- but the actual function is `move_done_tasks`.
require('todotxt').move_done = require('todotxt').move_done_tasks

vim.keymap.set(
    'n',
    '<leader>tn',
    '<cmd>TodoTxt new<cr>',
    { desc = 'New todo entry' }
)
vim.keymap.set(
    'n',
    '<leader>tt',
    '<cmd>TodoTxt<cr>',
    { desc = 'Toggle todo.txt' }
)
vim.keymap.set(
    'n',
    '<leader>td',
    '<cmd>DoneTxt<cr>',
    { desc = 'Toggle done.txt' }
)
vim.keymap.set(
    'n',
    '<leader>tg',
    '<cmd>TodoTxt ghost<cr>',
    { desc = 'Toggle ghost text' }
)
