local function gh(repo) return 'https://github.com/' .. repo end

-- AI CLI integration: attach to `pi` (or other CLI agents) running in a
-- persistent tmux or Herdr pane from inside Neovim. `pi` is one of sidekick's built-in
-- preconfigured tools, so no `cli.tools.pi` entry is needed here.
--
-- NES (Copilot "Next Edit Suggestions") is left disabled: we already get
-- inline suggestions from copilot.lua, and NES is a separate/bigger feature
-- (multi-spot edit suggestions elsewhere in the buffer) that would need its
-- own opt-in decision later, not a fix for anything currently missing.
vim.pack.add({ gh('folke/sidekick.nvim') })

local herdr = require('juan.herdr')
local in_herdr = herdr.active()

require('sidekick').setup({
    nes = { enabled = false },
    cli = {
        watch = true, -- reload buffers when pi edits files on disk
        picker = 'telescope', -- we have telescope, not snacks.nvim
        mux = {
            -- This option is restricted to Sidekick's built-in muxes.
            -- Herdr actions use explicit registered session states below.
            backend = 'tmux',
            enabled = not in_herdr,
            -- New sessions are real multiplexer splits alongside nvim,
            -- not editor-owned embedded terminal buffers.
            create = 'split',
        },
    },
})

local adapter
if in_herdr then
    adapter = require('juan.sidekick_herdr')
    require('sidekick.cli.session').register('herdr', adapter)
end

-- External Herdr panes are not Neovim terminal buffers: focus them explicitly.
local function toggle(options)
    if not in_herdr then return require('sidekick.cli').toggle(options) end
    adapter.with_session(
        function(state) herdr.focus(state.session.herdr_pane_id) end,
        { name = options and options.name }
    )
end

local function select_tool()
    if not in_herdr then return require('sidekick.cli').select() end
    adapter.with_session(
        function(state) herdr.focus(state.session.herdr_pane_id) end,
        { select = true }
    )
end

local function send(options)
    local cli = require('sidekick.cli')
    if not in_herdr then return cli.send(options) end
    -- Capture buffer/visual context before opening the session picker.
    local text = options.text
    if not text then
        local message
        message, text = cli.render(options)
        if message == '' or not text then
            require('sidekick.util').warn('Nothing to send.')
            return
        end
        if message == '\n' then text = {} end
    end
    adapter.with_session(
        function(state)
            cli.send({
                text = text,
                submit = options.submit,
                filter = { session = state.session.id },
            })
        end,
        { name = options.name }
    )
end

local function prompt()
    local cli = require('sidekick.cli')
    if not in_herdr then return cli.prompt() end
    cli.prompt({
        cb = function(_, text)
            if text then send({ text = text }) end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

vim.keymap.set(
    'n',
    '<leader>aa',
    function() toggle() end,
    { desc = 'Toggle AI CLI' }
)
vim.keymap.set('n', '<leader>as', select_tool, { desc = 'Select AI CLI tool' })
vim.keymap.set(
    'n',
    '<leader>aP',
    function() toggle({ name = 'pi', focus = true }) end,
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
    function() send({ msg = '{this}' }) end,
    { desc = 'Send this to AI CLI' }
)
vim.keymap.set(
    'n',
    '<leader>af',
    function() send({ msg = '{file}' }) end,
    { desc = 'Send file to AI CLI' }
)
vim.keymap.set(
    'x',
    '<leader>av',
    function() send({ msg = '{selection}' }) end,
    { desc = 'Send selection to AI CLI' }
)
vim.keymap.set(
    { 'n', 'x' },
    '<leader>ap',
    prompt,
    { desc = 'Select AI CLI prompt' }
)

-- vim: ts=2 sts=2 sw=2 et
