-- Load plugin modules in order.

-- require 'plugins.gruvbox'
-- require 'plugins.vscode'
-- require 'plugins.catppuccin'
require('plugins.everforest')
require('plugins.guess-indent')
require('plugins.gitsigns')
require('plugins.which-key')
-- require 'plugins.tokyonight'
require('plugins.todo-comments')
require('plugins.mini')
require('plugins.telescope')
require('plugins.lspconfig')
require('plugins.conform')
require('plugins.blink-cmp')
require('plugins.treesitter')

-- The following comments only work if you have downloaded the kickstart repo, not just copy pasted the
-- init.lua. If you want these files, they are in the repository, so you can just download them and
-- place them in the correct locations.

-- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
--
--  Here are some example plugins that I've included in the Kickstart repository.
--  Uncomment any of the lines below to enable them (you will need to restart nvim).
--
-- require 'plugins.debug'
require('plugins.indent_line')
require('plugins.lint')
require('plugins.autopairs')
require('plugins.neo-tree')
-- require 'plugins.gitsigns' -- adds gitsigns recommended keymaps

-- NOTE: You can add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
--
--  Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
-- require 'custom.plugins'

require('plugins.todotxt')
require('plugins.sneak')
require('plugins.vim-slime')
require('plugins.undotree')
require('plugins.softwrap')
require('plugins.markdown')
require('plugins.image')
require('plugins.render-markdown')
require('plugins.copilot')
require('plugins.sidekick')
require('plugins.yazi')
require('plugins.lazygit')
require('plugins.autolist')
-- require('plugins.tmux')
require('plugins.beancount')

require('plugins.large_file')
require('plugins.smear-cursor')
-- require('plugins.treesitter-context')
require('plugins.dropbar')
