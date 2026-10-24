-- Startup-only matrix: never contact a live multiplexer or start a model.
vim.opt.rtp:prepend(assert(vim.env.HERDR_TEST_REPO) .. '/.config/nvim')
vim.opt.rtp:append(assert(vim.env.HERDR_TEST_SIDEKICK))
vim.pack.add = function() end
local errors, checked = {}, {}
vim.notify = function(message, level)
    if level and level >= vim.log.levels.ERROR then
        errors[#errors + 1] = tostring(message)
    end
end
local Config = require('sidekick.config')
local validate = Config.validate
Config.validate = function(key, expected)
    checked[key] = true
    return validate(key, expected)
end
require('plugins.vim-slime')
require('plugins.sidekick')
assert(
    vim.wait(1000, function() return checked['nes.diff.show'] end, 5),
    'Deferred Sidekick validation never ran'
)
-- Validation errors themselves are notified on the next scheduled callback.
vim.wait(50, function() return #errors > 0 end, 5)
assert(#errors == 0, table.concat(errors, '\n'))
local target = vim.g.slime_target or 'none'
assert(target == vim.env.HERDR_TEST_EXPECT_SLIME, target)
local in_herdr = require('juan.herdr').active()
assert(
    Config.cli.mux.backend == 'tmux',
    'Never put a custom name in the built-in mux enum'
)
assert(Config.cli.mux.enabled == not in_herdr)
assert((require('sidekick.cli.session').backends.herdr ~= nil) == in_herdr)
local route = in_herdr and 'herdr' or Config.cli.mux.backend
assert(route == vim.env.HERDR_TEST_EXPECT_SIDEKICK)
assert(vim.v.errmsg == '', vim.v.errmsg)
print(
    'PASS deferred startup validation: Slime='
        .. target
        .. ', Sidekick route='
        .. route
)
vim.cmd('qa!')
