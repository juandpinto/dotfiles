vim.pack.add({ 'https://github.com/rickhowe/wrapwidth' })

-- Automatically set the wrapwidth column based on textwidth
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile", "BufEnter", "FileType"}, {
  pattern = "*",
  callback = function()
    -- Set the specific wrap column for the current buffer
    vim.cmd("Wrapwidth 80")
  end,
})

-- require('wrapwidth').setup({
--     config = function()
--         vim.g.wrapwidth_default = 80
--     end
-- })
