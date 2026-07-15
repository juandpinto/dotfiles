-- [[ image.nvim ]]
--  Renders actual images (not ascii/blocks) inline in the terminal for
--  markdown files, using WezTerm's Kitty graphics protocol support.
--
--  Requires `config.enable_kitty_graphics = true` in `~/.wezterm.lua`
--  (already set) and ImageMagick (`brew install imagemagick`, already
--  installed on this machine).
--
--  NOTE: image.nvim's own docs flag WezTerm's Kitty graphics protocol
--  support as not fully compliant/slower than Kitty/Ghostty itself. If
--  images render incorrectly or the buffer feels sluggish, switch
--  `backend` below to `'sixel'` (WezTerm also supports Sixel) -- slower
--  still, but more compliant; pair it with `only_render_image_at_cursor`
--  (already enabled below) to keep it usable.
vim.pack.add({ 'https://github.com/3rd/image.nvim' })

require('image').setup({
    backend = 'kitty',

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
