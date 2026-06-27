local function gh(repo) return 'https://github.com/' .. repo end

-- [[ Colorscheme ]]
-- gruvbox-material: a modified version of gruvbox with softer colors.
-- Styles: 'hard', 'medium' (default), 'soft'
-- See :help gruvbox-material for full options.
vim.pack.add { gh 'sainnhe/gruvbox-material' }
vim.g.gruvbox_material_background = 'medium'
vim.g.gruvbox_material_foreground = 'material'
vim.g.gruvbox_material_better_performance = 1
-- transparent_background=2 clears Normal, NormalNC, NormalFloat, StatusLine, etc.
vim.g.gruvbox_material_transparent_background = 2

vim.pack.add { gh 'f-person/auto-dark-mode.nvim' }

-- Clear listchar backgrounds and dim the space/whitespace dots and indent guides.
-- fg colors are picked to be subtle against each background.
local function clear_listchar_backgrounds(mode)
	local dim_fg = mode == 'dark' and '#504945' or '#d5c4a1'
	for _, group in ipairs({ 'NonText', 'EndOfBuffer' }) do
		vim.api.nvim_set_hl(0, group, { bg = 'none' })
	end
	vim.api.nvim_set_hl(0, 'Whitespace', { bg = 'none', fg = dim_fg })
	vim.api.nvim_set_hl(0, 'IblIndent', { fg = dim_fg, nocombine = true })
	vim.api.nvim_set_hl(0, 'IblScope', { fg = dim_fg, nocombine = true })
end

-- gruvbox-material supports both dark and light via vim.o.background.
-- background must be set BEFORE colorscheme (per :help gruvbox-material).
require('auto-dark-mode').setup({
	update_interval = 1000,
	set_dark_mode = function()
		vim.o.background = 'dark'
		vim.cmd.colorscheme('gruvbox-material')
		clear_listchar_backgrounds('dark')
	end,
	set_light_mode = function()
		vim.o.background = 'light'
		vim.cmd.colorscheme('gruvbox-material')
		clear_listchar_backgrounds('light')
	end,
})

