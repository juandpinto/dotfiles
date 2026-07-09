-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic Config & Keymaps
--  See `:help vim.diagnostic.Opts`
vim.diagnostic.config({
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = { min = vim.diagnostic.severity.WARN } },

    -- Can switch between these as you prefer
    virtual_text = false, -- Text shows up at the end of the line
    virtual_lines = false, -- Text shows up underneath the line, with virtual lines

    -- Auto open the float, so you can easily read the errors when jumping with `[d` and `]d`
    jump = {
        on_jump = function(_, bufnr)
            vim.diagnostic.open_float({
                bufnr = bufnr,
                scope = 'cursor',
                focus = false,
            })
        end,
    },
})

vim.keymap.set(
    'n',
    '<leader>q',
    vim.diagnostic.setloclist,
    { desc = 'Open diagnostic [Q]uickfix list' }
)

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set(
    't',
    '<Esc><Esc>',
    '<C-\\><C-n>',
    { desc = 'Exit terminal mode' }
)

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set(
    'n',
    '<C-h>',
    '<C-w><C-h>',
    { desc = 'Move focus to the left window' }
)
vim.keymap.set(
    'n',
    '<C-l>',
    '<C-w><C-l>',
    { desc = 'Move focus to the right window' }
)
vim.keymap.set(
    'n',
    '<C-j>',
    '<C-w><C-j>',
    { desc = 'Move focus to the lower window' }
)
vim.keymap.set(
    'n',
    '<C-k>',
    '<C-w><C-k>',
    { desc = 'Move focus to the upper window' }
)

-- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
-- vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
-- vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
-- vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
-- vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking (copying) text',
    group = vim.api.nvim_create_augroup(
        'kickstart-highlight-yank',
        { clear = true }
    ),
    callback = function() vim.hl.on_yank() end,
})

-- Move line up and down
vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv")
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv")

vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

vim.keymap.set('n', 'n', 'nzzzv')
vim.keymap.set('n', 'N', 'Nzzzv')

-- Disable Ex mode completely
vim.keymap.set('n', 'Q', '<nop>')

-- Delete operations go to void register by default
vim.keymap.set({ 'n', 'v' }, 'd', '"_d', { desc = 'Delete to void' })
vim.keymap.set({ 'n', 'v' }, 'D', '"_D', { desc = 'Delete line to void' })
vim.keymap.set({ 'n', 'v' }, 'c', '"_c', { desc = 'Change to void' })
vim.keymap.set({ 'n', 'v' }, 'C', '"_C', { desc = 'Change line to void' })
vim.keymap.set({ 'n', 'v' }, 'x', '"_x', { desc = 'Delete char to void' })

-- Preserve system clipboard functionality with Leader key
vim.keymap.set(
    { 'n', 'v' },
    '<leader>d',
    '+d',
    { desc = 'Cut to system clipboard' }
)
vim.keymap.set(
    { 'n', 'v' },
    '<leader>D',
    '+D',
    { desc = 'Cut line to system clipboard' }
)

-- Paste over text without overwriting your clipboard register
vim.keymap.set(
    'x',
    'p',
    '"_dP',
    { desc = 'Paste over without losing clipboard' }
)

-- Toggle wrap
vim.keymap.set(
    'n',
    '<leader>tz',
    function() vim.wo.wrap = not vim.wo.wrap end,
    { desc = 'Toggle [T]ext [Z]ap wrap' }
)

-- Move through wrapped lines with arrow keys
vim.keymap.set({ 'n', 'v' }, '<Up>', 'gk', { noremap = true, silent = true })
vim.keymap.set({ 'n', 'v' }, '<Down>', 'gj', { noremap = true, silent = true })
vim.keymap.set('i', '<Up>', '<C-o>gk', { noremap = true, silent = true })
vim.keymap.set('i', '<Down>', '<C-o>gj', { noremap = true, silent = true })

-- Split tmux vertically in the current file's directory
vim.keymap.set('n', '<leader>tv', function()
  local current_file_dir = vim.fn.expand('%:p:h')
  vim.fn.system(string.format('tmux split-window -h -c "%s"', current_file_dir))
end, { desc = 'Tmux split vertical in file dir' })
