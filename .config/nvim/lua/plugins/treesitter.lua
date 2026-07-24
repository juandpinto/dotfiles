local function gh(repo) return 'https://github.com/' .. repo end

-- [[ Configure Treesitter ]]
--  Used to highlight, edit, and navigate code
--
--  See `:help nvim-treesitter-intro`

-- NOTE: You can also specify a branch or a specific commit
vim.pack.add({
    { src = gh('nvim-treesitter/nvim-treesitter'), version = 'main' },
})

-- Ensure basic parsers are installed
local parsers = {
    'bash',
    'c',
    'diff',
    'html',
    'lua',
    'luadoc',
    'markdown',
    'markdown_inline',
    'query',
    'vim',
    'vimdoc',
    'todotxt',
    'xml',
}
require('nvim-treesitter').install(parsers)

---@param buf integer
---@param language string
local function treesitter_try_attach(buf, language)
    -- Check if a parser exists and load it
    if not vim.treesitter.language.add(language) then return end
    -- Enable syntax highlighting and other treesitter features
    vim.treesitter.start(buf, language)

    -- Enable treesitter based folds
    -- For more info on folds see `:help folds`
    -- vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    -- vim.wo.foldmethod = 'expr'

    -- Check if treesitter indentation is available for this language, and if so enable it
    -- in case there is no indent query, the indentexpr will fallback to the vim's built in one
    -- local has_indent_query = vim.treesitter.query.get(language, 'indents') ~= nil

    -- Enable treesitter based indentation
    -- if has_indent_query then vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
end

-- Rainbow CSV (see plugins.rainbow_csv) highlights CSV/TSV columns using
-- legacy `:syntax` matches (priority 50). Treesitter highlights (priority
-- 100, see `vim.highlight.priorities`) always render on top of those, and
-- tree-sitter-csv's own highlight query is coarse enough (just text vs.
-- number vs. delimiter) that it would paint over Rainbow CSV's per-column
-- colors on every buffer. Skip Treesitter for these filetypes so Rainbow
-- CSV's highlighting is the one that's actually visible.
local skip_treesitter_filetypes = {
    csv = true,
    tsv = true,
    csv_semicolon = true,
    csv_whitespace = true,
    csv_pipe = true,
    rfc_csv = true,
    rfc_semicolon = true,
}

local available_parsers = require('nvim-treesitter').get_available()
vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
        local buf, filetype = args.buf, args.match
        if skip_treesitter_filetypes[filetype] then return end

        local language = vim.treesitter.language.get_lang(filetype)
        if not language then return end

        local installed_parsers =
            require('nvim-treesitter').get_installed('parsers')

        if vim.tbl_contains(installed_parsers, language) then
            -- Enable the parser if it is already installed
            treesitter_try_attach(buf, language)
        elseif vim.tbl_contains(available_parsers, language) then
            -- If a parser is available in `nvim-treesitter`, auto-install it and enable it after the installation is done
            require('nvim-treesitter')
                .install(language)
                :await(function() treesitter_try_attach(buf, language) end)
        else
            -- Try to enable treesitter features in case the parser exists but is not available from `nvim-treesitter`
            treesitter_try_attach(buf, language)
        end
    end,
})
