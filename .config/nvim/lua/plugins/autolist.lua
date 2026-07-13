vim.pack.add({ 'https://github.com/gaoDean/autolist.nvim' })

require('autolist').setup()

-- Scoped to only the filetypes autolist actually has list patterns for
-- (see its `lists` config: markdown, text, norg, tex, plaintex). Left
-- global, these mappings hijack <Tab>/<S-Tab> in every filetype (e.g.
-- Python), overriding blink.cmp's own <Tab> snippet-jump/fallback mapping,
-- and `AutolistTab`'s internal `<C-t>` simulation leaves the cursor one
-- column short in buffers with no actual list to indent.
vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'markdown', 'text', 'norg', 'tex', 'plaintex' },
    callback = function(ev)
        local opts = { buffer = ev.buf }
        vim.keymap.set('i', '<tab>', '<cmd>AutolistTab<cr>', opts)
        vim.keymap.set('i', '<s-tab>', '<cmd>AutolistShiftTab<cr>', opts)
    end,
})
-- vim.keymap.set("i", "<c-t>", "<c-t><cmd>AutolistRecalculate<cr>") -- an example of using <c-t> to indent
vim.keymap.set('i', '<CR>', '<CR><cmd>AutolistNewBullet<cr>')
vim.keymap.set('n', 'o', 'o<cmd>AutolistNewBullet<cr>')
vim.keymap.set('n', 'O', 'O<cmd>AutolistNewBulletBefore<cr>')
vim.keymap.set('n', '<CR>', '<cmd>AutolistToggleCheckbox<cr><CR>')
vim.keymap.set('n', '<leader>cr', '<cmd>AutolistRecalculate<cr>')

-- cycle list types with dot-repeat
vim.keymap.set(
    'n',
    '<leader>cn',
    require('autolist').cycle_next_dr,
    { expr = true }
)
vim.keymap.set(
    'n',
    '<leader>cp',
    require('autolist').cycle_prev_dr,
    { expr = true }
)

-- if you don't want dot-repeat
-- vim.keymap.set("n", "<leader>cn", "<cmd>AutolistCycleNext<cr>")
-- vim.keymap.set("n", "<leader>cp", "<cmd>AutolistCycleNext<cr>")

-- functions to recalculate list on edit
vim.keymap.set('n', '>>', '>><cmd>AutolistRecalculate<cr>')
vim.keymap.set('n', '<<', '<<<cmd>AutolistRecalculate<cr>')
vim.keymap.set('n', 'dd', 'dd<cmd>AutolistRecalculate<cr>')
vim.keymap.set('v', 'd', 'd<cmd>AutolistRecalculate<cr>')
