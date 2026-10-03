local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add({ gh('jakewvincent/mkdnflow.nvim') })

-- Foam resolves links by workspace identity rather than only by a literal
-- filesystem path. For example, [[learner-models]] resolves to a page under
-- concepts/, while [[insights-lab/overview]] resolves to projects/insights-
-- lab/overview.md. Mkdnflow normally treats both as paths under the notebook
-- root, so it would otherwise create empty files for these existing pages.
-- Preserve explicit/relative/external paths, but resolve a unique existing
-- target anywhere in the wiki. Ambiguous names are left alone rather than
-- guessed.
local foam_root

local function resolve_foam_path(path)
    -- Mkdnflow's wiki-link parser can mistake the table-cell pipe after a
    -- bare link for the link's alias separator, leaving `]]` and padding
    -- spaces in the extracted source. Normalize that parser artifact before
    -- resolving the target.
    path = path:match('^(.-)%]%]') or path
    path = path:gsub('%s+$', '')

    if
        path == ''
        or path:match('^[/%.~]')
        or path:match('^#')
        or path:match('^%a[%w+%.%-]*:')
    then
        return path
    end

    -- Notebook dead-link/backlink scans run from libuv callbacks, where Nvim
    -- buffer APIs are forbidden. Mkdnflow exposes its resolved root as plain
    -- Lua state, so use that when already available and only inspect the
    -- current buffer during normal editor events.
    local mkdnflow = require('mkdnflow')
    local root
    local current_dir
    if vim.in_fast_event() then
        root = foam_root or mkdnflow.root_dir
    else
        root = mkdnflow.root_dir
        local current_file = vim.api.nvim_buf_get_name(0)
        current_dir = vim.fs.dirname(current_file)
        if (not root or root == '') and current_dir and current_dir ~= '' then
            local index = vim.fs.find('index.md', {
                path = current_dir,
                upward = true,
                type = 'file',
                limit = 1,
            })[1]
            root = index and vim.fs.dirname(index) or nil
        end
        foam_root = root
    end
    if not root or root == '' then return path end

    local target = path:match('%.[^./]+$') and path or path .. '.md'

    -- Prefer a literal same-directory page, then an explicitly root-level
    -- page. This preserves ordinary relative/path behavior when it exists.
    if current_dir and current_dir ~= '' then
        local local_candidate = vim.fs.joinpath(current_dir, target)
        if vim.fn.filereadable(local_candidate) == 1 then
            return local_candidate
        end
    end

    local root_candidate = vim.fs.joinpath(root, target)
    if vim.fn.filereadable(root_candidate) == 1 then return root_candidate end

    -- Foam also permits a path alias that omits an intermediate directory,
    -- such as `insights-lab/overview` for `projects/insights-lab/overview.md`.
    -- Search by basename, then keep only exact suffix matches.
    local filename = target:match('[^/\\]+$')
    local root_prefix = root:gsub('/$', '') .. '/'
    local matches = {}
    for _, candidate in
        ipairs(vim.fs.find(filename, {
            path = root,
            type = 'file',
            limit = 100,
        }))
    do
        local relative = candidate:sub(#root_prefix + 1)
        if
            relative == target
            or relative:sub(-#target - 1) == '/' .. target
        then
            table.insert(matches, candidate)
        end
    end

    return #matches == 1 and matches[1] or path
end

require('mkdnflow').setup({
    on_attach = function()
        -- Cache the resolved root for Mkdnflow's asynchronous notebook scans.
        foam_root = require('mkdnflow').root_dir
    end,
    modules = {
        -- Keep Markdown rendering/conceal behavior with the existing
        -- markdown.nvim and render-markdown.nvim configuration.
        conceal = false,
        folds = false,
        foldtext = false,
        completion = true,
        notebook = true,
        backlinks = true,
    },
    path_resolution = {
        -- mh-wiki uses Foam-style paths rooted at the repository, even when
        -- links appear in nested directories (for example [[data/kyron]]).
        primary = 'root',
        fallback = 'current',
        root_marker = 'index.md',
        sync_cwd = false,
        update_on_navigate = false,
    },
    links = {
        style = 'wiki',
        implicit_extension = 'md',
        transform_on_follow = resolve_foam_path,
        -- Do not turn ordinary text under the cursor into a link when using
        -- the context-sensitive Enter mapping.
        auto_create = false,
    },
    tables = {
        -- Prettier/markdownlint remains the canonical table formatter. Do not
        -- silently rewrite tables just by moving through them.
        format_on_move = false,
    },
    mappings = {
        -- Context-sensitive Enter handles list continuation, table row
        -- navigation, and following links. It intentionally replaces the
        -- previous Markdown list mappings.
        MkdnEnter = { { 'i', 'n', 'v' }, '<CR>' },

        -- Preserve native forward navigation; Back is useful for wiki history,
        -- but the Delete key should keep its normal meaning.
        MkdnGoForward = false,

        -- Keep markdown.nvim's heading navigation mappings. Mkdnflow's
        -- implementations are equivalent, but having one owner is clearer.
        MkdnNextHeading = false,
        MkdnPrevHeading = false,
        MkdnNextHeadingSame = false,
        MkdnPrevHeadingSame = false,

        -- Keep <leader>f available for Conform formatting rather than folding.
        MkdnFoldSection = false,
        MkdnUnfoldSection = false,

        -- Preserve normal Vim arithmetic and the existing REPL mapping.
        MkdnIncreaseHeading = false,
        MkdnDecreaseHeading = false,
        MkdnIncreaseHeadingOp = false,
        MkdnDecreaseHeadingOp = false,
        MkdnUpdateNumbering = false,

        -- Preserve normal yank behavior and vim-slime's <leader>p prefix.
        MkdnYankAnchorLink = false,
        MkdnYankFileAnchorLink = false,
        MkdnCreateLinkFromClipboard = false,

        -- Use Mkdnflow's context-sensitive wrappers in Markdown buffers. They
        -- handle tables and list indentation without stealing these keys from
        -- other filetypes.
        MkdnTableNextCell = false,
        MkdnTablePrevCell = false,
        MkdnTab = { 'i', '<Tab>' },
        MkdnSTab = { 'i', '<S-Tab>' },

        -- Wiki traversal and structural checks.
        MkdnBacklinks = { 'n', '<leader>mb' },
        MkdnDeadLinks = { 'n', '<leader>md' },
    },
})
