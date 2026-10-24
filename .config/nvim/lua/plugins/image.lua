-- [[ image.nvim ]]
--  Renders actual images (not ascii/blocks) inline in the terminal for
--  markdown files. Kitty is the Linux terminal; WezTerm remains the Mac fallback.
--
--  Requires ImageMagick (Linux package or `brew install imagemagick`).
--  WezTerm also needs `config.enable_kitty_graphics = true` (already set).
--
--  NOTE: image.nvim's own docs flag WezTerm's Kitty graphics protocol
--  support as not fully compliant/slower than Kitty/Ghostty itself. If
--  images render incorrectly or the buffer feels sluggish, switch
--  `backend` below to `'sixel'` (WezTerm also supports Sixel) -- slower
--  still, but more compliant; pair it with `only_render_image_at_cursor`
--  (already enabled below) to keep it usable.
vim.pack.add({ 'https://github.com/3rd/image.nvim' })

local function setup_image()
    require('image').setup({
        backend = 'kitty',
        processor = 'magick_cli', -- ImageMagick CLI; no architecture-specific Lua rock
        tmux_show_only_in_active_window = true,

        integrations = {
            markdown = {
                enabled = true,
                -- Only draw the image the cursor is currently on top of, in a
                -- popup. Keeps things fast and avoids fighting with
                -- render-markdown.nvim's own (icon-only) handling of images.
                only_render_image_at_cursor = true,
                only_render_image_at_cursor_mode = 'popup',
                filetypes = { 'markdown' },
            },
        },

        max_width_window_percentage = 80,
        max_height_window_percentage = 50,
    })
end

-- Headless commands have no terminal geometry. Defer until an actual UI exists.
if #vim.api.nvim_list_uis() > 0 then
    setup_image()
else
    vim.api.nvim_create_autocmd(
        'UIEnter',
        { once = true, callback = setup_image }
    )
end
