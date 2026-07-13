local function gh(repo) return 'https://github.com/' .. repo end

-- AI CLI integration: attach to `pi` (or other CLI agents) running in a
-- tmux pane/window from inside Neovim. `pi` is one of sidekick's built-in
-- preconfigured tools, so no `cli.tools.pi` entry is needed here.
--
-- NES (Copilot "Next Edit Suggestions") is left disabled: we already get
-- inline suggestions from copilot.lua, and NES is a separate/bigger feature
-- (multi-spot edit suggestions elsewhere in the buffer) that would need its
-- own opt-in decision later, not a fix for anything currently missing.
vim.pack.add({ gh('folke/sidekick.nvim') })

require('sidekick').setup({
    nes = { enabled = false },
    cli = {
        watch = true, -- reload buffers when pi edits files on disk
        picker = 'telescope', -- we have telescope, not snacks.nvim
        mux = {
            backend = 'tmux',
            enabled = true,
            -- Open new sessions as a real tmux split (matches "pi in a tmux
            -- pane alongside nvim"), not an embedded Neovim terminal buffer.
            create = 'split',
        },
    },
})

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

vim.keymap.set(
    'n',
    '<leader>aa',
    function() require('sidekick.cli').toggle() end,
    { desc = 'Toggle AI CLI' }
)
vim.keymap.set(
    'n',
    '<leader>as',
    function() require('sidekick.cli').select() end,
    { desc = 'Select AI CLI tool' }
)
vim.keymap.set(
    'n',
    '<leader>aP',
    function() require('sidekick.cli').toggle({ name = 'pi', focus = true }) end,
    { desc = 'Toggle pi' }
)
vim.keymap.set(
    'n',
    '<leader>ad',
    function() require('sidekick.cli').close() end,
    { desc = 'Detach AI CLI session' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>at',
    function() require('sidekick.cli').send({ msg = '{this}' }) end,
    { desc = 'Send this to AI CLI' }
)
vim.keymap.set(
    'n',
    '<leader>af',
    function() require('sidekick.cli').send({ msg = '{file}' }) end,
    { desc = 'Send file to AI CLI' }
)
vim.keymap.set(
    'x',
    '<leader>av',
    function() require('sidekick.cli').send({ msg = '{selection}' }) end,
    { desc = 'Send selection to AI CLI' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>ap',
    function() require('sidekick.cli').prompt() end,
    { desc = 'Select AI CLI prompt' }
)

-- vim: ts=2 sts=2 sw=2 et
