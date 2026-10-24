-- Invoked only by test_herdr_port.mjs against its private Herdr server.
local root = assert(vim.env.HERDR_TEST_REPO)
vim.opt.rtp:prepend(root .. '/.config/nvim')
vim.opt.rtp:append(assert(vim.env.HERDR_TEST_SLIME))
local h = require('juan.herdr')
assert(h.active())
assert(h.current().pane_id == vim.env.HERDR_PANE_ID)
local old_tmux = vim.env.TMUX
vim.env.TMUX = '/test/macos-tmux'
assert(not h.active(), 'Inner tmux must retain precedence')
vim.env.TMUX = old_tmux

vim.g.slime_target = 'herdr'
vim.g.slime_bracketed_paste = 1
vim.g.slime_dont_ask_default = 1
vim.cmd('runtime plugin/slime.vim')
vim.cmd('filetype plugin on')
vim.bo.filetype = 'python'
local command = vim.env.HERDR_TEST_IPYTHON_COMMAND
h.start_repl(command)
local target = vim.b.slime_config.pane_id
assert(target ~= h.current().pane_id)
local function read()
    return h.request('pane.read', {
        pane_id = target,
        source = 'recent',
        lines = 200,
        format = 'text',
        strip_ansi = true,
    }).read.text
end
local function wait_for(text, timeout)
    assert(
        vim.wait(
            timeout or 10000,
            function() return read():find(text, 1, true) ~= nil end,
            100
        ),
        'Missing test output: ' .. text .. '\n' .. read()
    )
end
wait_for('In [1]:')
assert(h.find_repl() == target, 'Existing IPython must be discoverable')
local before = #h.panes()
h.start_repl(command)
assert(
    #h.panes() == before,
    'Starting an existing REPL must not create another'
)

vim.fn['slime#send']('from pathlib import Path\nprint("HERDR_PORT_READY")\n')
wait_for('HERDR_PORT_READY')
-- Queue only after execution has actually started, not while prompt_toolkit is
-- still collecting the preceding paste. Use private marker files as evidence.
local busy = vim.fn.getcwd() .. '/busy-started'
local interrupt = vim.fn.getcwd() .. '/interrupt-started'
vim.fn['slime#send'](
    'import time\nPath('
        .. vim.json.encode(busy)
        .. ').write_text(str(get_ipython().execution_count))\nstart=time.monotonic()\nwhile time.monotonic()-start < 1.2:\n    pass\n'
)
assert(
    vim.wait(5000, function() return vim.fn.filereadable(busy) == 1 end, 20),
    read()
)
vim.fn['slime#send'](
    'def herdr_probe():\n    return 42\n\nanswer=herdr_probe()\nprint("QUEUED_RESULT", answer)\nprint("QUEUED_CELL_COUNT", get_ipython().execution_count)\n'
)
wait_for('QUEUED_RESULT 42')
local busy_count = assert(tonumber(vim.fn.readfile(busy)[1]))
wait_for('QUEUED_CELL_COUNT ' .. (busy_count + 1))
assert(not read():find('IndentationError', 1, true), read())

vim.fn['slime#send'](
    'Path('
        .. vim.json.encode(interrupt)
        .. ').touch()\nwhile True:\n    pass\n'
)
assert(
    vim.wait(
        5000,
        function() return vim.fn.filereadable(interrupt) == 1 end,
        20
    ),
    read()
)
vim.fn['slime#send']('\003')
wait_for('KeyboardInterrupt')
vim.fn['slime#send']('print("INTERRUPT_RECOVERED")\n')
wait_for('INTERRUPT_RECOVERED')
-- Focus uses an explicit pane ID, not whichever pane another client focused.
h.focus(target)
assert(h.request('pane.get', { pane_id = target }).pane.focused)
h.focus(vim.env.HERDR_PANE_ID)
assert(not pcall(h.target, { pane_id = vim.env.HERDR_PANE_ID }))
assert(not pcall(h.target, { pane_id = 'w999:p999' }))
print(
    'PASS live Slime: startup, discovery, no duplicate REPL, queued multiline paste, interrupt, focus, stale/self guards'
)

-- Exercise Sidekick's real public registration API with a mocked transport.
vim.opt.rtp:append(assert(vim.env.HERDR_TEST_SIDEKICK))
local errors, checked = {}, {}
vim.notify = function(message, level)
    if level and level >= vim.log.levels.ERROR then
        errors[#errors + 1] = tostring(message)
    end
end
local Config = require('sidekick.config')
local validate = Config.validate
Config.validate = function(key, expected)
    checked[key] = true
    return validate(key, expected)
end
local pack_add = vim.pack.add
vim.pack.add = function() end -- The installed plugin is already on this fixture's runtime path.
require('plugins.sidekick')
vim.pack.add = pack_add
assert(vim.wait(1000, function() return checked['nes.diff.show'] end, 5))
vim.wait(50, function() return #errors > 0 end, 5)
assert(#errors == 0, table.concat(errors, '\n'))
assert(Config.cli.mux.backend == 'tmux' and not Config.cli.mux.enabled)
local backend = require('juan.sidekick_herdr')
local Session = require('sidekick.cli.session')
Session.register('herdr', backend)
local original_request, original_split, original_current =
    h.request, h.split, h.current
local calls = {}
h.current = function() return { workspace_id = 'test-space' } end
h.split = function() return { pane_id = 'test-space:p2' } end
h.request = function(method, params)
    calls[#calls + 1] = { method = method, params = params }
    if method == 'agent.list' then
        return {
            agents = {
                {
                    agent = 'pi',
                    pane_id = 'test-space:p2',
                    workspace_id = 'test-space',
                    cwd = '/tmp',
                },
                {
                    agent = 'pi',
                    pane_id = 'other:p1',
                    workspace_id = 'other',
                    cwd = '/private',
                },
            },
        }
    elseif method == 'pane.get' then
        return { pane = { agent = 'pi', agent_status = 'idle' } }
    end
    return {}
end
assert(#backend.sessions() == 1, 'Discovery must stay in this workspace')
local session = Session.new({ tool = 'pi', backend = 'herdr', cwd = '/tmp' })
session:start()
assert(session.external and session.herdr_pane_id == 'test-space:p2')
session:send('hello\n')
session:submit()
assert(session:is_running())
local count = #calls
session:detach()
assert(#calls == count, 'Detach must not stop the pane or agent')
assert(calls[#calls - 1].method == 'pane.send_keys')
-- The actual adapter entry point must create a Herdr session even though
-- the built-in mux is disabled. Do not let it fall back to an editor terminal.
local State = require('sidekick.cli.state')
local state_get = State.get
State.get = function(filter)
    if filter and filter.attached then return {} end
    return { { tool = Config.get_tool('pi'), installed = true } }
end
local attached
backend.with_session(function(state) attached = state end, { name = 'pi' })
assert(vim.wait(1000, function() return attached ~= nil end, 5))
assert(attached.session.backend == 'herdr' and attached.session.external)
assert(attached.session:is_attached())
assert(
    not attached.terminal,
    'A persistent Herdr agent must not become an editor-owned terminal'
)
-- Test the real keymap routing, not just direct Session.new calls.
local function mapping(description)
    for _, value in ipairs(vim.api.nvim_get_keymap('n')) do
        if value.desc == description then return assert(value.callback) end
    end
    error('Missing mapping: ' .. description)
end
local route_trace = {}
State.get = function(filter)
    if filter and filter.attached then
        local states =
            vim.tbl_map(State.get_state, vim.tbl_values(Session.attached()))
        route_trace[#route_trace + 1] = { filter = filter, count = #states }
        return states
    end
    route_trace[#route_trace + 1] = { filter = filter, count = 2 }
    return {
        { tool = Config.get_tool('pi'), installed = true },
        { tool = Config.get_tool('claude'), installed = true },
    }
end
mapping('Toggle pi')()
assert(
    vim.wait(
        1000,
        function() return calls[#calls].method == 'pane.focus' end,
        5
    )
)
State.detach(attached)

local Cli = require('sidekick.cli')
local render, select_ui = Cli.render, vim.ui.select
local context = 'captured before selection'
Cli.render = function() return render({ msg = context }) end
local choose, choices
vim.ui.select = function(items, _, callback)
    choices, choose = items, callback
end
calls = {}
mapping('Send this to AI CLI')()
assert(choose and #choices == 2, 'A new Herdr tool must use the adapter picker')
assert(#calls == 0, 'Do not launch or paste before the user chooses')
context = 'changed after selection'
choose(choices[1])
local delivered
assert(
    vim.wait(1000, function()
        for _, call in ipairs(calls) do
            if call.method == 'pane.send_text' then
                delivered = call.params.text
                return true
            end
        end
        return false
    end, 5),
    'Mapped send failed: '
        .. vim.inspect(calls)
        .. '\n'
        .. vim.inspect(route_trace)
        .. '\n'
        .. table.concat(errors, '\n')
        .. '\n'
        .. vim.v.errmsg
)
assert(delivered:find('captured before selection', 1, true))
assert(not delivered:find('changed after selection', 1, true))
for _, value in pairs(Session.attached()) do
    assert(value.backend == 'herdr' and value.external)
end
Cli.render, vim.ui.select = render, select_ui

-- Prompt selection must take the same persistent-session path.
local prompt = Cli.prompt
Cli.prompt = function(opts)
    local message, text = render({ msg = 'selected test prompt' })
    opts.cb(message, text)
end
calls = {}
mapping('Select AI CLI prompt')()
assert(vim.wait(1000, function()
    for _, call in ipairs(calls) do
        if
            call.method == 'pane.send_text'
            and call.params.text:find('selected test prompt', 1, true)
        then
            return true
        end
    end
    return false
end, 5))
Cli.prompt = prompt

-- Cancelling explicit selection must not create or focus any pane.
choose = nil
vim.ui.select = function(_, _, callback) choose = callback end
calls = {}
mapping('Select AI CLI tool')()
assert(choose)
choose(nil)
vim.wait(30)
assert(#calls == 0)
vim.ui.select = select_ui
for _, value in pairs(Session.attached()) do
    State.detach(State.get_state(value))
end
State.get = state_get

h.request, h.split, h.current =
    original_request, original_split, original_current
vim.wait(50, function() return #errors > 0 end, 5)
assert(#errors == 0, table.concat(errors, '\n'))
assert(vim.v.errmsg == '', vim.v.errmsg)
print(
    'PASS Sidekick: deferred validation, explicit Herdr creation, mapped focus/context/prompt/cancellation, persistent lifecycle and non-destructive detach'
)
vim.cmd('qa!')
