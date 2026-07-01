# AGENTS.md

Personal macOS dotfiles repo for `juan.pinto`. No build, test, lint, or CI
pipeline — there is nothing to "run" here, just config files that get
symlinked into `$HOME`.

## Symlink model (no stow/chezmoi, no install script)

- Setup is **manual symlinks**, not stow/chezmoi, and there is no bootstrap
  script in this repo. Don't assume one exists.
- Top-level dotfiles are symlinked directly: `~/.zshrc`, `~/.p10k.zsh`,
  `~/.wezterm.lua` -> `~/.dotfiles/<file>`.
- `~/.config` itself is a **real directory**, not a symlink. Each tool under
  `.config/` is symlinked individually, e.g.
  `~/.config/nvim -> ../.dotfiles/.config/nvim`. If you add a new tool config
  here, it won't take effect until someone manually creates the matching
  symlink under `~/.config/<tool>`.

## `.config/opencode/` is the live global OpenCode config

- This isn't project-local config — it's the actual `~/.config/opencode`
  used by every OpenCode session on this machine. Changes here have
  machine-wide effect, not just within this repo.
- When editing `opencode.jsonc`, anything under `skills/`, or anything
  agent/plugin-related, use the **customize-opencode** skill.
- `node_modules/`, `package.json`, `package-lock.json`, and `bun.lock` under
  `.config/opencode/` are gitignored (its own local `.gitignore`) — they
  exist locally for the `@opencode-ai/plugin` dependency but are not meant
  to be committed.

## Git submodules

- Two real submodules: `fzf-git.sh` and `.config/tmux/plugins/tpm`. After a
  fresh clone, run `git submodule update --init`.
- `.config/tmux/plugins/*` is gitignored except `tpm` (tmux's plugin
  manager, TPM, installs the rest at runtime — they're not vendored here).

## Neovim config

- Uses Neovim's built-in `vim.pack` plugin manager (not lazy.nvim/packer).
  Plugin pins live in `.config/nvim/nvim-pack-lock.json`.
- Entry point is `.config/nvim/init.lua`, which wires up
  `lua/options.lua`, `lua/keymaps.lua`, `lua/pack.lua`, and `lua/plugins.lua`
  (+ per-plugin configs under `lua/plugins/`).
- Lua is formatted with StyLua using `.config/stylua/stylua.toml`
  (4-space indent, column width 80, single quotes preferred) — this is a
  global StyLua config (symlinked to `~/.config/stylua`), not unique to this
  repo's Lua files.

## Other global tool configs symlinked from here

- `.config/ruff/ruff.toml` is the machine-wide Ruff config (line length 80,
  double quotes, ignores `E402`/`F704` to tolerate notebook-style scripts).
  It's not a lint config for this repo's own code — there is no Python here.
- Root `.markdownlint.jsonc` applies to Markdown anywhere markdownlint is
  invoked relative to this repo (e.g. `MD013`/line-length and several other
  rules are disabled; `MD007` indent is 4).

## Existing skills (don't duplicate their guidance here)

`.config/opencode/skills/` already covers: `documentation` (Markdown style
for data-science docs), `python` (DS Python conventions), `mh-wiki` (McGraw
Hill personal wiki operations), `grill-me` (plan-stress-testing interview
flow). Prefer updating those files over adding overlapping notes here.
