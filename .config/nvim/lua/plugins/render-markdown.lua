-- [[ render-markdown.nvim ]]
--  Renders markdown in-buffer (headings, bullets, checkboxes, tables,
--  code blocks, block quotes, etc.) using conceal/extmarks -- no external
--  process or browser required.
--
--  Off by default (`enabled = false` below): markdown buffers open raw and
--  `<leader>mp` toggles rendering on/off for that buffer only. When turned
--  on, the line under the cursor still falls back to raw text
--  (anti-conceal), and insert mode shows raw text too.
--
--  Depends on the `markdown`/`markdown_inline` treesitter parsers (see
--  `plugins.treesitter`) and `mini.icons` (see `plugins.mini`) for code
--  block language icons, both already installed in this config.
vim.pack.add({
    'https://github.com/MeanderingProgrammer/render-markdown.nvim',
})

require('render-markdown').setup({
    -- Don't render markdown until explicitly toggled on (see `<leader>mp`
    -- below). Only affects the default state; buffer-local toggling still
    -- works normally on top of this.
    enabled = false,
})

-- Buffer-local keymaps for markdown files only.
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'markdown',
    group = vim.api.nvim_create_augroup('render-markdown-keymaps', { clear = true }),
    callback = function(args)
        local buf_opts = { buffer = args.buf }

        -- Toggle the in-buffer rendering on/off for this buffer.
        vim.keymap.set(
            'n',
            '<leader>mp',
            function() require('render-markdown').buf_toggle() end,
            vim.tbl_extend(
                'force',
                buf_opts,
                { desc = 'Toggle rendered markdown (this buffer)' }
            )
        )

        -- Open the fully rendered buffer in a side split, raw source stays
        -- put in the current window.
        vim.keymap.set(
            'n',
            '<leader>mv',
            function() require('render-markdown').preview() end,
            vim.tbl_extend(
                'force',
                buf_opts,
                { desc = 'Rendered markdown preview (side split)' }
            )
        )

        -- Read-only, fully rendered look via the `glow` CLI in a terminal
        -- split -- closest to how the file would render on GitHub/etc.
        -- Install with `brew install glow`.
        vim.keymap.set('n', '<leader>mg', function()
            if vim.fn.executable('glow') == 0 then
                vim.notify(
                    'glow not found on PATH: install with `brew install glow`',
                    vim.log.levels.WARN
                )
                return
            end
            vim.cmd(
                'vsplit | terminal glow --style dark '
                    .. vim.fn.expand('%:p')
            )
        end, vim.tbl_extend(
            'force',
            buf_opts,
            { desc = 'Glow preview (read-only, full render)' }
        ))
    end,
})
