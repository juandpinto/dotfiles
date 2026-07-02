local function gh(repo) return 'https://github.com/' .. repo end

-- [[ mini.nvim ]]
--  A collection of various small independent plugins/modules
vim.pack.add({ gh('nvim-mini/mini.nvim') })

-- If a nerd font is available, load the icons module for pretty icons in various plugins.
if vim.g.have_nerd_font then
    require('mini.icons').setup()
    -- Used for backwards compatibility with plugins that require `nvim-web-devicons` (e.g. telescope.nvim)
    MiniIcons.mock_nvim_web_devicons()
end

-- Better Around/Inside textobjects
--
-- Examples:
--  - va)  - [V]isually select [A]round [)]paren
--  - yiiq - [Y]ank [I]nside [I]+1 [Q]uote
--  - ci'  - [C]hange [I]nside [']quote
require('mini.ai').setup({
    -- NOTE: Avoid conflicts with the built-in incremental selection mappings on Neovim>=0.12 (see `:help treesitter-incremental-selection`)
    mappings = {
        around_next = 'aa',
        inside_next = 'ii',
    },
    n_lines = 500,
})

-- Add/delete/replace surroundings (brackets, quotes, etc.)
--
-- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
-- - sd'   - [S]urround [D]elete [']quotes
-- - sr)'  - [S]urround [R]eplace [)] [']
require('mini.surround').setup()

-- Simple and easy statusline.
--  You could remove this setup call if you don't like it,
--  and try some other statusline plugin
local statusline = require('mini.statusline')
-- Set `use_icons` to true if you have a Nerd Font
statusline.setup({ use_icons = vim.g.have_nerd_font })

-- You can configure sections in the statusline by overriding their
-- default behavior. For example, here we set the section for
-- cursor location to LINE:COLUMN
---@diagnostic disable-next-line: duplicate-set-field
statusline.section_location = function() return '%2l:%-2v %p%%' end

-- Override the active statusline to include the opencode server status on the
-- right side.  `require('opencode').statusline()` returns a Nerd Font icon +
-- server URL when connected (e.g. "󰚩 localhost:42187"), or just the
-- disconnected icon ("󱚧") when no server is found.  The pcall guards against
-- the plugin not being loaded yet on initial renders.
---@diagnostic disable-next-line: duplicate-set-field
MiniStatusline.active = function()
    local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
    local git = MiniStatusline.section_git({ trunc_width = 75 })
    local diff = MiniStatusline.section_diff({ trunc_width = 75 })
    local diagnostics = MiniStatusline.section_diagnostics({ trunc_width = 75 })
    local lsp = MiniStatusline.section_lsp({ trunc_width = 75 })
    local filename = MiniStatusline.section_filename({ trunc_width = 140 })
    local fileinfo = MiniStatusline.section_fileinfo({ trunc_width = 120 })
    local location = MiniStatusline.section_location({ trunc_width = 75 })
    local search = MiniStatusline.section_searchcount({ trunc_width = 75 })

    local ok, oc = pcall(function() return require('opencode').statusline() end)
    local opencode = ok and oc or ''

    return MiniStatusline.combine_groups({
        { hl = mode_hl, strings = { mode } },
        {
            hl = 'MiniStatuslineDevinfo',
            strings = { git, diff, diagnostics, lsp },
        },
        '%<',
        { hl = 'MiniStatuslineFilename', strings = { filename } },
        '%=',
        { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
        { hl = 'MiniStatuslineFileinfo', strings = { opencode } },
        { hl = mode_hl, strings = { search, location } },
    })
end

-- ... and there is more!
--  Check out: https://github.com/nvim-mini/mini.nvim

require('mini.files').setup({ windows = { preview = true } })

-- vim.keymap.set('n', '<leader>e', function() MiniFiles.open(vim.uv.cwd()) end)
vim.keymap.set('n', '<leader>e', function()
    local buf_name = vim.api.nvim_buf_get_name(0)
    local path = vim.fn.filereadable(buf_name) == 1 and buf_name
        or vim.fn.getcwd()
    MiniFiles.open(path)
    MiniFiles.reveal_cwd()
end, { desc = 'Open Mini Files' })

-- Set focused directory as current working directory
local set_cwd = function()
    local path = (MiniFiles.get_fs_entry() or {}).path
    if path == nil then return vim.notify('Cursor is not on valid entry') end
    vim.fn.chdir(vim.fs.dirname(path))
end

-- Yank in register full path of entry under cursor
local yank_full_path = function()
    local path = (MiniFiles.get_fs_entry() or {}).path
    if path == nil then return vim.notify('Cursor is not on valid entry') end
    vim.fn.setreg(vim.v.register, path)
end

-- Yank in register relative path of entry under cursor
local yank_relative_path = function()
    local path = (MiniFiles.get_fs_entry() or {}).path
    if path == nil then return vim.notify('Cursor is not on valid entry') end
    path = vim.fn.fnamemodify(path, ':.')
    vim.fn.setreg(vim.v.register, path)
end

-- Open path with system default handler (useful for non-text files)
local ui_open = function() vim.ui.open(MiniFiles.get_fs_entry().path) end

vim.api.nvim_create_autocmd('User', {
    pattern = 'MiniFilesBufferCreate',
    callback = function(args)
        local b = args.data.buf_id
        vim.keymap.set('n', 'g~', set_cwd, { buffer = b, desc = 'Set cwd' })
        vim.keymap.set('n', 'gX', ui_open, { buffer = b, desc = 'OS open' })
        vim.keymap.set(
            'n',
            'gyy',
            yank_full_path,
            { buffer = b, desc = 'Yank full path' }
        )
        vim.keymap.set(
            'n',
            'gyr',
            yank_relative_path,
            { buffer = b, desc = 'Yank relative path' }
        )
    end,
})

require('mini.sessions').setup()
