vim.pack.add({ "https://github.com/phrmendes/todotxt.nvim" })

vim.filetype.add({
  filename = {
    ["todo.txt"] = "todotxt",
    ["done.txt"] = "todotxt",
  },
})

require("todotxt").setup({
  -- todotxt = vim.env.HOME .. "/Documents/notes/todo.txt",
  -- donetxt = vim.env.HOME .. "/Documents/notes/done.txt",
  max_priority = "C",
  metadata = {
    tag = { sort = "asc" },
    due = { sort = "asc" },
  },
  ghost_text = {
    enable = true,
    mappings = {
      ["(A)"] = "today",
      ["(B)"] = "tomorrow",
      ["(C)"] = "this week",
    },
  },
})

vim.keymap.set("n", "<leader>tn", "<cmd>TodoTxt new<cr>", { desc = "New todo entry" })
vim.keymap.set("n", "<leader>tt", "<cmd>TodoTxt<cr>", { desc = "Toggle todo.txt" })
vim.keymap.set("n", "<leader>td", "<cmd>DoneTxt<cr>", { desc = "Toggle done.txt" })
vim.keymap.set("n", "<leader>tg", "<cmd>TodoTxt ghost<cr>", { desc = "Toggle ghost text" })
