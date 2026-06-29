vim.pack.add({ 'https://github.com/mikavilpas/yazi.nvim' })

vim.keymap.set("n", "<leader>y", function()
  require("yazi").yazi()
end, { desc = "Open yazi" })

