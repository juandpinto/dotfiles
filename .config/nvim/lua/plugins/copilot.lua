vim.pack.add({ 'https://github.com/zbirenbaum/copilot.lua' })

require('copilot').setup({
    suggestion = {
        enabled = true,
        auto_trigger = true, -- ghost text as you type, matching previous copilot.vim behavior
        keymap = {
            -- <Tab> collides with autolist.nvim's list-indent mapping, so accept
            -- suggestions with <C-l> instead (same key as before the switch).
            accept = '<C-l>',
            accept_word = '<C-Right>', -- partial accept, one word at a time
            accept_line = false,
            next = '<M-]>',
            prev = '<M-[>',
            dismiss = '<C-]>',
        },
    },
})
