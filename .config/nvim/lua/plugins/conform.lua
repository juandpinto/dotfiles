local function gh(repo) return 'https://github.com/' .. repo end

-- [[ Formatting ]]
vim.pack.add { gh 'stevearc/conform.nvim' }
require('conform').setup {
  notify_on_error = true,
  format_on_save = function(bufnr)
    -- You can specify filetypes to autoformat on save here:
    local enabled_filetypes = {
      -- lua = true,
      -- python = true,
    }
    if enabled_filetypes[vim.bo[bufnr].filetype] then
      return { timeout_ms = 500 }
    else
      return nil
    end
  end,
  default_format_opts = {
    lsp_format = 'fallback', -- Use external formatters if configured below, otherwise use LSP formatting. Set to `false` to disable LSP formatting entirely.
  },
  -- You can also specify external formatters in here.
  formatters_by_ft = {
    ['*'] = { 'trim_whitespace' }, -- strip trailing whitespace on every save
    -- rust = { 'rustfmt' },
    -- Conform can also run multiple formatters sequentially
    -- python = { "isort", "black" },
    python = { 'ruff_fix', 'ruff_format' },
    markdown = { 'prettier', 'markdownlint' }, -- prettier first for table formatting, markdownlint second as primary
    lua = { 'stylua' },
    json = { 'prettier' },
    --
    -- You can use 'stop_after_first' to run the first available formatter from the list
    -- javascript = { "prettierd", "prettier", stop_after_first = true },
  },
  formatters = {
    markdownlint = {
      args = { '--fix', '--config', vim.fn.expand '~/.markdownlint.jsonc', '$FILENAME' },
    },
    prettier = {
      -- Preserve prose line wrapping to avoid conflicts with markdownlint and long-line conventions
      prepend_args = { '--prose-wrap', 'preserve' },
    },
  },
}

vim.keymap.set({ 'n', 'v' }, '<leader>f', function() require('conform').format { async = true } end, { desc = '[F]ormat buffer' })
