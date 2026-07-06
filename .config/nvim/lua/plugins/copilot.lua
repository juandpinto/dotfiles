vim.pack.add({ 'https://github.com/github/copilot.vim' })

-- require("copilot").setup( {} )

-- Disable the default <Tab> accept mapping (it collides with
-- autolist.nvim's <Tab>/<S-Tab> list-indent mappings) and use <C-l>
-- to accept suggestions instead.
vim.g.copilot_no_tab_map = true
vim.keymap.set('i', '<C-l>', 'copilot#Accept("\\<CR>")', {
    expr = true,
    replace_keycodes = false,
    desc = 'Accept Copilot suggestion',
})
