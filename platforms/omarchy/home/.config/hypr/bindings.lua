-- Replace the all-themes picker shortcut with the requested two-theme toggle.
-- The full picker remains available as `omarchy theme switcher`.
hl.unbind("SUPER + SHIFT + CTRL + SPACE")
o.bind("SUPER + SHIFT + CTRL + SPACE", "Everforest dark/light",
    os.getenv("HOME") .. "/.local/bin/everforest toggle")

-- strata-installer: file-manager start
hl.unbind("SUPER + SHIFT + F")
hl.unbind("SUPER + ALT + SHIFT + F")
o.bind("SUPER + SHIFT + F", "File manager", { launch = os.getenv("HOME") .. "/.local/bin/strata" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)",
  "uwsm-app -- " .. os.getenv("HOME") .. "/.local/bin/strata \"$(omarchy-cmd-terminal-cwd)\"")
-- strata-installer: file-manager end

-- Apple Music webapp shortcut
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", { webapp = "https://music.apple.com", focus = true })

-- Track workspace visits; Hyprland exposes only the immediately previous workspace.
local workspace_history = {}
local cycle_index

local function remember_workspace(workspace)
  if not workspace or workspace.id <= 0 then return end
  for i, id in ipairs(workspace_history) do
    if id == workspace.id then
      table.remove(workspace_history, i)
      break
    end
  end
  table.insert(workspace_history, 1, workspace.id)
end

-- Seed older visits from window focus order; subsequent workspace changes are tracked directly.
for _, workspace in ipairs(hl.get_workspaces()) do remember_workspace(workspace) end
local windows = hl.get_windows()
table.sort(windows, function(a, b)
  local a_rank = a.focus_history_id < 0 and math.huge or a.focus_history_id
  local b_rank = b.focus_history_id < 0 and math.huge or b.focus_history_id
  return a_rank > b_rank
end)
for _, window in ipairs(windows) do remember_workspace(window.workspace) end
remember_workspace(hl.get_last_workspace())
remember_workspace(hl.get_active_workspace())

hl.on("workspace.active", function(workspace)
  if not cycle_index then remember_workspace(workspace) end
end)
hl.on("monitor.focused", function()
  if not cycle_index then remember_workspace(hl.get_active_workspace()) end
end)

-- Hold Super and tap Tab repeatedly to walk a frozen visit order; release to reset the cycle.
hl.on("input.keyboard.key", function(keycode, _, state)
  if state == 0 and (keycode == 133 or keycode == 134) and cycle_index then
    cycle_index = nil
    remember_workspace(hl.get_active_workspace())
  end
end)

hl.unbind("SUPER + TAB") -- was: Next workspace in numeric order
o.bind("SUPER + TAB", "Cycle through recently visited workspaces", function()
  if not cycle_index then
    remember_workspace(hl.get_active_workspace())
    cycle_index = 1
  end
  if #workspace_history < 2 then
    cycle_index = nil
    return
  end
  cycle_index = cycle_index % #workspace_history + 1
  hl.dispatch(hl.dsp.focus({ workspace = tostring(workspace_history[cycle_index]) }))
end)

-- fathom: begin. Loading the overlay alone does not bind Alt+Tab.
do
  local fathom = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.mtolhuys.fathom/hypr/fathom.lua"
  local file = io.open(fathom, "r")
  if file then
    file:close()
    pcall(dofile, fathom)
  end
end
-- fathom: end

-- >>> omamail default mail client, do not edit by hand
hl.unbind("SUPER + SHIFT + E")
hl.unbind("SUPER + SHIFT + ALT + E")
o.bind("SUPER + SHIFT + E", "Email", "omarchy-shell shell summon omamail '{}'")
o.bind("SUPER + SHIFT + ALT + E", "New email", "omarchy-shell shell summon omamail '{\"compose\":true}'")
-- <<< omamail default mail client

 o.bind("SUPER + SHIFT + T", "Todoist", { webapp = "https://app.todoist.com", focus = true })
