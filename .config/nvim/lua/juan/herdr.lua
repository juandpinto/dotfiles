-- Small Herdr socket client shared by Slime, Sidekick, and split/focus mappings.
-- No shell interpolation, extra daemon, tmux emulation, or automatic retries.
local M = {}
local sequence = 0
local repl

function M.active()
    return vim.env.HERDR_ENV == '1'
        and not (vim.env.TMUX and vim.env.TMUX ~= '')
        and vim.env.HERDR_SOCKET_PATH ~= nil
end

function M.request(method, params)
    assert(M.active(), 'Not in a Herdr pane outside tmux')
    sequence = sequence + 1
    local id = 'nvim:' .. vim.fn.getpid() .. ':' .. sequence
    local response, closed, buffer = nil, false, ''
    local channel = vim.fn.sockconnect('pipe', vim.env.HERDR_SOCKET_PATH, {
        on_data = function(_, data)
            buffer = buffer .. table.concat(data, '\n')
            local line = buffer:match('([^\n]+)\n')
            if line then
                local ok, value = pcall(vim.json.decode, line)
                if ok and value.id == id then response = value end
            end
        end,
        on_close = function() closed = true end,
    })
    assert(channel > 0, 'Cannot connect to the inherited Herdr socket')
    local ok, result = pcall(function()
        vim.fn.chansend(channel, vim.json.encode({
            id = id,
            method = method,
            params = params or vim.empty_dict(),
        }) .. '\n')
        vim.wait(2000, function() return response ~= nil or closed end, 5)
        assert(
            response,
            'Herdr ' .. method .. ' timed out; delivery is unknown, not retried'
        )
        assert(
            not response.error,
            'Herdr: ' .. (response.error and response.error.message or '')
        )
        return response.result
    end)
    pcall(vim.fn.chanclose, channel)
    if not ok then error(result, 0) end
    return result
end

function M.current()
    return M.request('pane.current', { caller_pane_id = vim.env.HERDR_PANE_ID }).pane
end

function M.panes()
    local current = M.current()
    return M.request('pane.list', { workspace_id = current.workspace_id }).panes,
        current
end

function M.focus(id) return M.request('pane.focus', { pane_id = id }) end

function M.split(opts)
    opts = opts or {}
    return M.request('pane.split', {
        target_pane_id = M.current().pane_id,
        direction = opts.direction or 'right',
        ratio = opts.ratio or 0.5,
        cwd = opts.cwd or vim.fn.getcwd(),
        focus = opts.focus == true,
    }).pane
end

-- Raw text is deliberate: explicit paste boundaries also protect cells queued
-- while IPython is busy, rather than depending on its momentary terminal mode.
function M.paste(id, text, submit)
    local pane = M.request('pane.get', { pane_id = id }).pane
    assert(
        pane.agent_status ~= 'blocked',
        'Target is waiting for approval; not sending input'
    )
    local bytes = '\027[200~' .. text .. '\027[201~'
    local result = M.request('pane.send_text', { pane_id = id, text = bytes })
    -- Herdr encodes Enter for the target's negotiated keyboard protocol.
    if submit then
        return M.request('pane.send_keys', { pane_id = id, keys = { 'enter' } })
    end
    return result
end

local function is_ipython(info)
    for _, process in ipairs(info.foreground_processes or {}) do
        local argv = process.argv or {}
        for i, arg in ipairs(argv) do
            if
                vim.fs.basename(arg) == 'ipython'
                or (arg == '-m' and argv[i + 1] == 'IPython')
            then
                return true
            end
        end
    end
    return false
end

function M.find_repl()
    local panes, current = M.panes()
    local found = {}
    for _, pane in ipairs(panes) do
        if
            pane.tab_id == current.tab_id
            and pane.pane_id ~= current.pane_id
            and not pane.agent
        then
            local info =
                M.request('pane.process_info', { pane_id = pane.pane_id })
            if is_ipython(info.process_info) then
                found[#found + 1] = pane.pane_id
            end
        end
    end
    if #found == 1 then return found[1] end
end

function M.target(config)
    local id = config and config.pane_id
    if not id or id == '' then id = repl or M.find_repl() end
    assert(
        id and id ~= '',
        'No unique IPython target; use <leader>rr or :SlimeConfig'
    )
    assert(
        id ~= M.current().pane_id,
        'Refusing to send REPL input to the editor pane'
    )
    local pane = M.request('pane.get', { pane_id = id }).pane
    assert(
        not pane.agent,
        'REPL target now contains an agent; select the intended REPL again'
    )
    return id
end

function M.configure_repl()
    local panes, current = M.panes()
    local choices, ids = { 'Choose a Herdr REPL pane:' }, {}
    for _, pane in ipairs(panes) do
        if pane.pane_id ~= current.pane_id and not pane.agent then
            ids[#ids + 1] = pane.pane_id
            choices[#choices + 1] =
                string.format('%d: %s  %s', #ids, pane.pane_id, pane.cwd or '')
        end
    end
    local selected = vim.fn.inputlist(choices)
    assert(ids[selected], 'No REPL pane selected')
    repl = ids[selected]
    return { pane_id = repl }
end

function M.start_repl(command)
    local config = vim.b.slime_config
    local id = config and config.pane_id
    if not id or id == '' then id = repl or M.find_repl() end
    if id then
        local info =
            M.request('pane.process_info', { pane_id = id }).process_info
        if is_ipython(info) then
            vim.b.slime_config = { pane_id = id }
            return -- Never type a shell command into an already-running REPL.
        end
        assert(
            info.foreground_process_group_id == info.shell_pid,
            'Configured target has a foreground command; not starting IPython there'
        )
    else
        id = M.split({ cwd = vim.fn.getcwd(), focus = false }).pane_id
    end
    local ok, err = pcall(M.request, 'pane.send_input', {
        pane_id = id,
        text = command:gsub('[\r\n]+$', ''),
        keys = { 'enter' },
    })
    if not ok then
        error('Created pane ' .. id .. ', but IPython startup failed: ' .. err)
    end
    M.request('pane.rename', { pane_id = id, label = 'IPython' })
    repl = id
    vim.b.slime_config = { pane_id = id }
end

function M.slime_send(config, text)
    local id = M.target(config)
    -- Interrupt, EOF, and redraw are keys, not pasted text.
    local controls =
        { ['\003'] = 'ctrl+c', ['\004'] = 'ctrl+d', ['\012'] = 'ctrl+l' }
    if controls[text] then
        return M.request(
            'pane.send_keys',
            { pane_id = id, keys = { controls[text] } }
        )
    end
    local paste = vim.fn['slime#common#bracketed_paste'](text)
    if paste[1] ~= 0 then return M.paste(id, paste[2], paste[3] ~= 0) end
    return M.request('pane.send_text', { pane_id = id, text = text })
end

return M
