vim.pack.add({ 'https://github.com/sheng-tse/jupynvim' })

require('jupynvim').setup()

local function current_notebook_json(buf)
    local notebook = require('jupynvim.notebook').get(buf)
    if not notebook then
        return nil, 'JupytextPercent requires an open jupynvim notebook'
    end

    notebook:sync_from_buffer()
    local embedded = require('jupynvim.notebook.embedded')
    local cells = {}
    for _, cell in ipairs(notebook.cells) do
        local source = cell.source or ''
        if cell.cell_type == 'markdown' then
            source = embedded.postprocess(cell.id, source)
        end
        table.insert(cells, {
            id = cell.id,
            cell_type = cell.cell_type or 'code',
            source = source,
        })
    end

    local client = require('jupynvim')._nb_client(notebook)
    local replace_err, replace_result = client:call_sync(
        'replace_cells',
        { session_id = notebook.session_id, cells = cells },
        5000
    )
    if replace_err then
        return nil, 'replace_cells failed: ' .. tostring(replace_err)
    end
    for i, id in ipairs((replace_result or {}).ids or {}) do
        if notebook.cells[i] then notebook.cells[i].id = id end
    end

    local snapshot_err, snapshot =
        client:call_sync('snapshot', { session_id = notebook.session_id }, 5000)
    if snapshot_err then
        return nil, 'snapshot failed: ' .. tostring(snapshot_err)
    end

    local function json_object(value)
        if value == nil or value == vim.NIL then return vim.empty_dict() end
        if type(value) == 'table' and next(value) == nil then
            return vim.empty_dict()
        end
        return value
    end

    -- Jupytext does not use notebook outputs, so omit them. This both keeps
    -- the conversion lightweight and avoids serializing arbitrary rich output.
    local exported_cells = {}
    for _, cell in ipairs(snapshot.cells or {}) do
        local exported = {
            cell_type = cell.cell_type,
            id = cell.id,
            metadata = json_object(cell.metadata),
            source = cell.source or '',
        }
        if cell.cell_type == 'code' then
            exported.execution_count = vim.NIL
            exported.outputs = {}
        end
        table.insert(exported_cells, exported)
    end

    local ok, json = pcall(vim.json.encode, {
        cells = exported_cells,
        metadata = json_object(snapshot.metadata),
        nbformat = 4,
        nbformat_minor = 5,
    })
    if not ok then
        return nil, 'could not serialize notebook: ' .. tostring(json)
    end
    return json
end

local function convert_to_percent_script(force)
    local buf = vim.api.nvim_get_current_buf()
    local path = vim.api.nvim_buf_get_name(buf)
    local extension = vim.fn.fnamemodify(path, ':e'):lower()
    if path == '' or extension ~= 'ipynb' then
        vim.notify(
            'JupytextPercent requires a local .ipynb buffer',
            vim.log.levels.ERROR
        )
        return
    end
    if path:match('^jupynvim://') then
        vim.notify(
            'JupytextPercent does not support remote notebooks',
            vim.log.levels.ERROR
        )
        return
    end
    if vim.fn.executable('uv') ~= 1 then
        vim.notify('JupytextPercent requires uv on PATH', vim.log.levels.ERROR)
        return
    end

    local script = vim.fn.fnamemodify(path, ':r') .. '.py'
    if not force and vim.uv.fs_stat(script) then
        local choice = vim.fn.confirm(
            script .. ' already exists. Overwrite it?',
            '&Overwrite\n&Cancel',
            2
        )
        if choice ~= 1 then return end
    end

    local notebook_json, err = current_notebook_json(buf)
    if not notebook_json then
        vim.notify(err, vim.log.levels.ERROR)
        return
    end

    vim.notify('Converting notebook to ' .. script, vim.log.levels.INFO)
    vim.system({
        'uv',
        'tool',
        'run',
        '--from',
        'jupytext',
        'jupytext',
        '--from',
        'ipynb',
        '--to',
        'py:percent',
        '--output',
        script,
    }, { stdin = notebook_json, text = true }, function(result)
        vim.schedule(function()
            if result.code == 0 then
                vim.cmd('vsplit ' .. vim.fn.fnameescape(script))
                vim.notify('Wrote ' .. script, vim.log.levels.INFO)
                return
            end

            local stderr = result.stderr or ''
            local stdout = result.stdout or ''
            local output = stderr ~= '' and stderr or stdout
            if output == '' then output = 'No output from jupytext.' end
            vim.notify(
                'Jupytext conversion failed:\n' .. vim.trim(output),
                vim.log.levels.ERROR
            )
        end)
    end)
end

vim.api.nvim_create_user_command(
    'JupytextPercent',
    function(command) convert_to_percent_script(command.bang) end,
    {
        bang = true,
        desc = 'Convert the current notebook state to a # %% Python script',
    }
)
