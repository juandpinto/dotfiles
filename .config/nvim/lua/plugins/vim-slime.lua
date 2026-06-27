vim.pack.add({ 'https://github.com/jpalardy/vim-slime' })

vim.g.slime_python_ipython = 1
vim.g.slime_dont_ask_default = 1

-- =========================================
-- Environment detection
-- =========================================
local function env(name)
  local val = vim.fn.getenv(name)
  return (val ~= vim.NIL and val ~= "") and val or nil
end

local _in_tmux = env("TMUX") ~= nil
local _in_wezterm = env("WEZTERM_PANE") ~= nil

-- Find the most recently active non-current pane in the same WezTerm tab.
-- Falls back to "1" if the CLI call fails or only one pane exists.
local function find_wezterm_target_pane()
  local current = env("WEZTERM_PANE")
  if not current then return "1" end

  local raw = vim.fn.system("wezterm cli list --format json 2>/dev/null")
  if vim.v.shell_error ~= 0 then return "1" end

  local ok, panes = pcall(vim.fn.json_decode, raw)
  if not ok or type(panes) ~= "table" then return "1" end

  -- Find which tab the current pane is on
  local current_tab
  for _, p in ipairs(panes) do
    if tostring(p.pane_id) == current then
      current_tab = p.tab_id
      break
    end
  end
  if not current_tab then return "1" end

  -- Return the first other pane in the same tab
  for _, p in ipairs(panes) do
    if p.tab_id == current_tab and tostring(p.pane_id) ~= current then
      return tostring(p.pane_id)
    end
  end
  return "1"
end

if _in_tmux then
  vim.g.slime_target = "tmux"
  vim.g.slime_default_config = { socket_name = "default", target_pane = "{last}" }
elseif _in_wezterm then
  vim.g.slime_target = "wezterm"
  vim.g.slime_default_config = { pane_id = find_wezterm_target_pane() }
end

-- =========================================
-- Cell utilities
-- =========================================
local function is_cell_marker(line)
  return line:match("^# ?%%") ~= nil  -- matches both "# %%" and "#%%"
end

local function get_cell_bounds()
  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local total_lines = vim.api.nvim_buf_line_count(buf)

  local cell_start = 1
  for i = cursor_line, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if is_cell_marker(line) then
      cell_start = i + 1
      break
    end
  end

  local cell_end = total_lines
  local next_cell_line = nil
  for i = cursor_line + 1, total_lines do
    local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1]
    if is_cell_marker(line) then
      cell_end = i - 1
      next_cell_line = i
      break
    end
  end

  return cell_start, cell_end, next_cell_line
end

local function send_cell(cell_start, cell_end)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, cell_start - 1, cell_end, false)
  vim.fn["slime#send"](table.concat(lines, "\n") .. "\n")
end

-- =========================================
-- Commands
-- =========================================
vim.api.nvim_create_user_command("RunPythonCell", function()
  local cell_start, cell_end, _ = get_cell_bounds()
  send_cell(cell_start, cell_end)
end, {})

vim.api.nvim_create_user_command("RunPythonCellAndAdvance", function()
  local buf = vim.api.nvim_get_current_buf()
  local cell_start, cell_end, next_cell_line = get_cell_bounds()
  send_cell(cell_start, cell_end)

  if next_cell_line then
    vim.api.nvim_win_set_cursor(0, { next_cell_line, 0 })
  else
    -- Last cell: skip the blank line prefix if the file already ends with one
    local total_lines = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, total_lines - 1, total_lines, false)[1]
    if last_line ~= '' then
      vim.api.nvim_buf_set_lines(buf, total_lines, total_lines, false, { "", "# %%", "" })
      vim.api.nvim_win_set_cursor(0, { total_lines + 2, 0 })
    else
      vim.api.nvim_buf_set_lines(buf, total_lines, total_lines, false, { "# %%", "" })
      vim.api.nvim_win_set_cursor(0, { total_lines + 1, 0 })
    end
  end
end, {})

-- Detect project context and send the appropriate `uv run ipython` command to
-- the target pane. Requires a shell to be running there (not an existing REPL).
vim.api.nvim_create_user_command("StartIPython", function()
  local cmd
  if vim.fn.executable('uv') == 1 then
    local in_project = vim.fn.findfile('pyproject.toml', '.;') ~= ''
    if in_project then
      cmd = 'uv run ipython --no-autoindent\n'
    else
      cmd = 'uvx ipython --no-autoindent\n'
    end
  else
    cmd = 'ipython --no-autoindent\n'
  end
  vim.fn["slime#send"](cmd)
end, {})

-- =========================================
-- Keybindings
-- =========================================

-- REPL lifecycle
vim.keymap.set('n', '<leader>rr', '<cmd>StartIPython<CR>',
  { silent = true, desc = 'REPL: start IPython' })
vim.keymap.set('n', '<leader>p<leader>', function() vim.fn["slime#send"]("\x03") end,
  { silent = true, desc = 'REPL: interrupt (Ctrl-C)' })
vim.keymap.set('n', '<leader>pq', function() vim.fn["slime#send"]("\x04") end,
  { silent = true, desc = 'REPL: exit (Ctrl-D)' })
vim.keymap.set('n', '<leader>cl', function() vim.fn["slime#send"]("\x0c") end,
  { silent = true, desc = 'REPL: clear screen' })
vim.keymap.set('n', '<leader>rf', function()
  if _in_tmux then
    vim.fn.system('tmux select-pane -l')
  elseif _in_wezterm then
    local cfg = vim.b.slime_config or vim.g.slime_default_config or {}
    local pane_id = cfg.pane_id or "1"
    vim.fn.system('wezterm cli activate-pane --pane-id=' .. pane_id)
  end
end, { silent = true, desc = 'REPL: focus pane' })

-- Sending code
vim.keymap.set('n', '<leader>rc', '<cmd>RunPythonCell<CR>',
  { silent = true, desc = 'REPL: run # %% cell' })
vim.keymap.set('n', '<leader>rn', '<cmd>RunPythonCellAndAdvance<CR>',
  { silent = true, desc = 'REPL: run # %% cell and advance' })
vim.keymap.set('x', '<leader>pv', '<Plug>SlimeRegionSend',
  { desc = 'REPL: send visual selection' })
vim.keymap.set('n', '<leader>pl', '<Plug>SlimeLineSend',
  { desc = 'REPL: send current line' })
vim.keymap.set('n', '<leader>pu', function()
  local buf = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, cursor_line, false)
  vim.fn["slime#send"](table.concat(lines, "\n") .. "\n")
end, { silent = true, desc = 'REPL: send from top of file to cursor' })

-- Output utilities (require 00-nvim-helpers.py in IPython startup)
vim.keymap.set('n', '<leader>rb', function() vim.fn["slime#send"]("show_html(_)\n") end,
  { silent = true, desc = 'REPL: open last result in browser' })
vim.keymap.set('n', '<leader>ri', function() vim.fn["slime#send"]("show_fig(preview=True)\n") end,
  { silent = true, desc = 'REPL: open figure in Preview' })
vim.keymap.set('n', '<leader>mcd', function()
  local dir = vim.fn.expand('%:p:h')
  vim.fn["slime#send"]("import os; os.chdir('" .. dir .. "')\n")
end, { silent = true, desc = 'REPL: cd to current file directory' })

