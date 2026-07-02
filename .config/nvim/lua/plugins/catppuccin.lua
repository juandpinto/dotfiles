vim.pack.add({ 'https://github.com/catppuccin/nvim' })

vim.pack.add({ 'https://github.com/f-person/auto-dark-mode.nvim' })

local function clear_background()
    -- Transparent background (override catppuccin's solid floats too)
    vim.api.nvim_set_hl(0, 'Normal', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'FloatBorder', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'Pmenu', { bg = 'NONE' })
end

require('catppuccin').setup({
    -- "auto" reads vim.o.background: "dark" → mocha, "light" → latte
    flavour = 'auto',
    background = {
        light = 'latte',
        dark = 'mocha',
    },
    transparent_background = true,
    default_integrations = true,
    integrations = {
        treesitter = true,
        gitsigns = true,
        which_key = true,
        blink_cmp = true,
        mini = { enabled = true },
        neo_tree = true,
        telescope = { enabled = true },
    },
})

-- auto-dark-mode.nvim sets vim.o.background, which catppuccin's flavour="auto" reads.
require('auto-dark-mode').setup({
    update_interval = 1000,
    set_dark_mode = function()
        vim.o.background = 'dark'
        vim.cmd.colorscheme('catppuccin')
        clear_background()
    end,
    set_light_mode = function()
        vim.o.background = 'light'
        vim.cmd.colorscheme('catppuccin')
        clear_background()
    end,
})
