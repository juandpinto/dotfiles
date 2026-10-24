-- Public Sidekick session backend. Herdr owns the PTYs; detach never kills Pi.
local Herdr = require('juan.herdr')
local M = {}
M.__index = M

function M:init()
    self.external = true
    self.priority = 20
end

local function agents()
    local workspace = Herdr.current().workspace_id
    return vim.tbl_filter(
        function(agent) return agent.workspace_id == workspace end,
        Herdr.request('agent.list').agents
    )
end

function M.sessions()
    local ret = {}
    local tools = require('sidekick.config').tools()
    for _, agent in ipairs(agents()) do
        if tools[agent.agent] then
            ret[#ret + 1] = {
                id = 'herdr:' .. agent.pane_id,
                cwd = agent.foreground_cwd or agent.cwd,
                tool = tools[agent.agent],
                herdr_pane_id = agent.pane_id,
                external = true,
            }
        end
    end
    return ret
end

-- Sidekick's setup accepts only tmux/zellij as global mux options. Create
-- explicit Herdr session states through the registry instead of bypassing that
-- validation or changing the meaning of a built-in backend name.
function M.with_session(callback, opts)
    opts = opts or {}
    local State = require('sidekick.cli.state')
    local Session = require('sidekick.cli.session')
    local function eligible(state)
        return state.installed
            and (not state.session or state.session.backend == 'herdr')
    end
    local filter = { name = opts.name }
    local choices = {}
    if not opts.select then
        choices = vim.tbl_filter(
            eligible,
            State.get({ attached = true, name = opts.name })
        )
    end
    if #choices == 0 then
        choices = vim.tbl_filter(eligible, State.get(filter))
    end
    if #choices == 0 then
        vim.notify(
            'No installed Herdr CLI tools match this selection',
            vim.log.levels.WARN
        )
        return
    end
    local use = vim.schedule_wrap(function(state)
        if not state then return end
        if not state.session then
            state.session =
                Session.new({ tool = state.tool, backend = 'herdr' })
        end
        callback(State.attach(state))
    end)
    if #choices == 1 and not opts.select then return use(choices[1]) end
    vim.ui.select(choices, {
        prompt = 'Select Herdr CLI tool:',
        format_item = function(state)
            if not state.session then
                return state.tool.name .. ' (new Herdr pane)'
            end
            return string.format(
                '%s [%s] %s',
                state.tool.name,
                state.session.herdr_pane_id,
                state.session.cwd
            )
        end,
    }, use)
end

function M:start()
    local config = require('sidekick.config').cli.mux
    local pane = Herdr.split({
        cwd = self.cwd,
        direction = config.split.vertical and 'right' or 'down',
        ratio = config.split.size <= 1 and config.split.size or 0.4,
        focus = false,
    })
    self.herdr_pane_id = pane.pane_id
    self.id = 'herdr:' .. pane.pane_id
    self.started_at = vim.uv.now()
    local argv = { 'env' }
    for key, value in pairs(self.tool.env or {}) do
        if value == false then
            vim.list_extend(argv, { '-u', key })
        else
            argv[#argv + 1] = key .. '=' .. tostring(value)
        end
    end
    vim.list_extend(argv, self.tool.cmd)
    local command = table.concat(vim.tbl_map(vim.fn.shellescape, argv), ' ')
    Herdr.request('pane.send_input', {
        pane_id = pane.pane_id,
        text = command,
        keys = { 'enter' },
    })
    self.started = true
end

function M:attach() end
function M:detach() end

function M:is_running()
    local ok, response =
        pcall(Herdr.request, 'pane.get', { pane_id = self.herdr_pane_id })
    if not ok then return false end
    return response.pane.agent == self.tool.name
        or (self.started_at ~= nil and vim.uv.now() - self.started_at < 10000)
end

function M:send(text) return Herdr.paste(self.herdr_pane_id, text, false) end

function M:submit()
    local pane =
        Herdr.request('pane.get', { pane_id = self.herdr_pane_id }).pane
    assert(
        pane.agent_status ~= 'blocked',
        'Agent is waiting for approval; not submitting'
    )
    return Herdr.request(
        'pane.send_keys',
        { pane_id = self.herdr_pane_id, keys = { 'enter' } }
    )
end

function M:dump()
    return Herdr.request('pane.read', {
        pane_id = self.herdr_pane_id,
        source = 'recent',
        lines = 100,
        format = 'text',
        strip_ansi = true,
    }).read.text
end

return M
