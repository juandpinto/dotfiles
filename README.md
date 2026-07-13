# Dotfiles

Personal macOS dotfiles for `juan.pinto`, managed with [GNU Stow](https://www.gnu.org/software/stow/). There's no bootstrap script or install target—setup is the handful of manual steps below.

## Prerequisites

- macOS
- [Homebrew](https://brew.sh)
- GNU Stow: `brew install stow`

## Setup on a new machine

1. Clone the repo to `~/.dotfiles`:

    ```bash
    git clone <repo-url> ~/.dotfiles
    cd ~/.dotfiles
    ```

2. Initialize submodules (`fzf-git.sh` and tmux's plugin manager, TPM):

    ```bash
    git submodule update --init
    ```

3. Stow everything into `$HOME`:

    ```bash
    stow -t ~ .
    ```

    `.stow-local-ignore` keeps `.git`, `.gitignore`, `.DS_Store`, and the root `README.md`/`AGENTS.md`/`package-lock.json` out of the link; those stay in the repo instead of linking into `$HOME`.

4. If `~/.config/<tool>` already exists as a real directory before you stow, rather than being created fresh by Stow, Stow folds into it and links files individually instead of linking the whole directory. That's expected, and it's exactly what happens with `~/.config/pi/agent`—see below.

## pi agent config

`~/.config/pi/agent` mixes stowed config (`AGENTS.md`, `extensions/`, `models.json`, `settings.json`, `skills/`) with files pi manages itself (`auth.json`, `sessions/`, `npm/`, `git/`). Those four are gitignored and intentionally not part of this repo: `npm/` and `git/` are pi's own package install/clone directories for whatever's listed in `settings.json`'s `packages` array, and `auth.json`/`sessions/` hold credentials and session history that shouldn't be shared across machines.

On a genuinely fresh machine, no manual step is needed for `npm/`/`git/`: just launch pi (or run `pi list`) after stowing, and it reads the already-stowed `settings.json` and installs any missing `packages` entries into fresh local directories automatically.

If you're migrating a machine that still has `~/.config/pi/agent/npm` or `~/.config/pi/agent/git` symlinked into this repo from before this convention existed, fix it once with:

```bash
test -L ~/.config/pi/agent/npm && rm ~/.config/pi/agent/npm
test -L ~/.config/pi/agent/git && rm ~/.config/pi/agent/git
rm -rf ~/.dotfiles/.config/pi/agent/npm ~/.dotfiles/.config/pi/agent/git
pi list   # or just launch pi; it reinstalls packages from settings.json
```

Then confirm both are real directories, not symlinks:

```bash
readlink ~/.config/pi/agent/npm   # prints nothing once fixed
readlink ~/.config/pi/agent/git   # prints nothing once fixed
```

## Other first-launch steps

- **Neovim**: uses the built-in `vim.pack` plugin manager; plugins install automatically the first time you launch `nvim`.
- **tmux**: plugins install via TPM; press `prefix + I` inside tmux on first use. `.config/tmux/plugins/*` other than `tpm` itself is gitignored—TPM installs the rest at runtime, they're not vendored here.
- **OpenCode**: `.config/opencode` has its own local `.gitignore` for `node_modules/`, `package.json`, `package-lock.json`, and `bun.lock` (needed for the `@opencode-ai/plugin` dependency). Run `npm install` inside `.config/opencode` if you need that dependency locally.

See `AGENTS.md` for more detail on the repo's structure and conventions.
