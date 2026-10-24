local M = {}

function M.setup()
    -- Optional Omarchy integration, not LazyVim: reuse its maintained clipboard
    -- provider for local Wayland, tmux, and SSH without blocking OSC52 reads.
    -- On macOS/other distributions the native clipboard provider is unchanged.
    if vim.fn.has('linux') ~= 1 then return end
    local helper = '/etc/skel/.config/nvim/lua/config/remote_clipboard.lua'
    if vim.fn.filereadable(helper) == 1 then
        local ok, provider = pcall(dofile, helper)
        if ok and type(provider) == 'table' then provider.setup() end
    end
end

return M
