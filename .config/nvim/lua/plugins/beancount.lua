local main_bean_file = vim.env.HOME .. '/Documents-local/beancount/1-pinto.bean'

-- Only load on machines where the beancount project exists
if vim.fn.filereadable(main_bean_file) ~= 1 then return end

vim.pack.add({ 'https://github.com/hxueh/beancount.nvim' })

-- Derive the Python path from the uv-managed venv in the beancount project dir.
-- Run `uv sync` in the project to create/update the venv.
local beancount_dir = vim.fn.fnamemodify(main_bean_file, ':h')
local python_path = beancount_dir .. '/.venv/bin/python'

-- Open all folds by default in beancount files
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'beancount',
    callback = function() vim.wo.foldlevel = 99 end,
})

require('beancount').setup({
    -- Alignment & formatting
    separator_column = 70, -- Column for decimal separator alignment
    instant_alignment = true, -- Align amounts on decimal point entry
    fixed_cjk_width = false, -- Treat CJK characters as 2-width
    auto_format_on_save = true, -- Auto formatting file on saving
    auto_fill_amounts = false, -- Auto-fill missing amounts on save (opt-in)

    -- Completion & input
    complete_payee_narration = true, -- Include payees/narrations

    -- Files & paths
    main_bean_file = main_bean_file,
    python_path = python_path, -- uv venv Python with beancount installed

    -- Diagnostics & warnings
    flag_warnings = { -- Transaction flag warning levels
        ['*'] = nil, -- FLAG_OKAY - Transactions that have been checked
        ['!'] = vim.diagnostic.severity.WARN, -- FLAG_WARNING - Mark by user as something to be looked at later
        ['P'] = nil, -- FLAG_PADDING - Transactions created from padding directives
        ['S'] = nil, -- FLAG_SUMMARIZE - Transactions created due to summarization
        ['T'] = nil, -- FLAG_TRANSFER - Transactions created due to balance transfers
        ['C'] = nil, -- FLAG_CONVERSIONS - Transactions created to account for price conversions
        ['M'] = nil, -- FLAG_MERGING - A flag to mark postings merging together legs for average cost
    },
    auto_save_before_check = true, -- Auto-save before diagnostics

    -- Features
    inlay_hints = true, -- Show inferred amounts
    snippets = {
        enabled = true, -- Enable snippet support
        date_format = '%Y-%m-%d', -- Date format for snippets
    },

    -- Key mappings (customizable)
    keymaps = {
        goto_definition = 'gd', -- Go to definition
        next_transaction = ']]', -- Next transaction
        prev_transaction = '[[', -- Previous transaction
    },

    -- UI settings
    ui = {
        virtual_text = true, -- Show diagnostics as virtual text
        signs = true, -- Show diagnostic signs
        update_in_insert = false, -- Don't update while typing
        severity_sort = true, -- Sort by severity
    },
})

-- beancount.setup() above calls `vim.diagnostic.config()` *globally*
-- (not scoped to its own namespace), which clobbers the virtual_text/etc.
-- preferences set in keymaps.lua for every filetype, not just beancount
-- buffers. Restore the global defaults, then re-apply virtual text scoped
-- to beancount's own diagnostic namespace so only .bean buffers keep it.
vim.diagnostic.config({ virtual_text = false })
vim.diagnostic.config(
    { virtual_text = true },
    vim.api.nvim_create_namespace('beancount-diagnostics')
)

-- Register beancount's blink.cmp completion source (accounts, payees,
-- narrations, commodities, tags, links). beancount.nvim only wires this up
-- automatically for lazy.nvim's dependency-opts pattern, which this
-- vim.pack-based config doesn't use, so it must be registered manually here.
-- Scoped to the beancount filetype so it doesn't affect other buffers.
local ok_blink, blink = pcall(require, 'blink.cmp')
if ok_blink then
    blink.add_source_provider('beancount', {
        name = 'beancount',
        module = 'beancount.completion.blink',
        score_offset = 100,
        opts = {
            trigger_characters = { ':', '#', '^', '"', ' ' },
        },
    })
    blink.add_filetype_source('beancount', 'beancount')
end
