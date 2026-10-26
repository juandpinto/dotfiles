# Dotfiles

Personal macOS and Omarchy/Asahi dotfiles for Juan Pinto. The original Mac layout is managed with [GNU Stow](https://www.gnu.org/software/stow/); shared Neovim/IPython configuration remains here, with Linux-specific files in a separate overlay.

**Linux:** follow [the Omarchy overlay guide](platforms/omarchy/README.md) and its selective `link.sh`. **Do not Stow the root package on Linux.** The Mac instructions below remain unchanged in scope. Both platforms use one `main` branch, not diverging OS branches. A small private companion repo (`~/.dotfiles-private`) holds the mail account configs, which contain addresses but no secrets; everything here is safe to be public.

This is my actual day-to-day setup, not a general-purpose framework, so it comes with strong personal opinions (Everforest theme everywhere, specific keybindings, an AI-coding-agent-heavy workflow via [pi](https://github.com/earendil-works/pi)) and machine-specific assumptions (macOS, Homebrew, zsh). It's public for reference—browse it for ideas or fork what's useful, but treat it as inspiration rather than something to install wholesale.

## What's inside

| Area               | Tool(s)                                                   |
|--------------------|-----------------------------------------------------------|
| Shell              | zsh (`.zshrc`), Starship prompt                           |
| Terminal           | Kitty + Herdr; WezTerm/tmux fallbacks                     |
| Editor             | Neovim (built-in `vim.pack`, no plugin-manager framework) |
| Window management  | AeroSpace, sketchybar                                     |
| Keyboard remapping | Karabiner-Elements                                        |
| File manager       | Yazi                                                      |
| System monitor     | btop                                                      |
| Email              | aerc                                                      |
| AI coding agent    | [pi](https://github.com/earendil-works/pi)                |
| Linting/formatting | Ruff (Python), StyLua (Lua), markdownlint                 |
| Diff/review        | hunk                                                      |

## macOS prerequisites

- macOS
- [Homebrew](https://brew.sh)
- GNU Stow: `brew install stow`

## macOS setup on a new machine

1. Clone the repo to `~/.dotfiles`:

    ```bash
    git clone https://github.com/juandpinto/dotfiles.git ~/.dotfiles
    cd ~/.dotfiles
    ```

2. Initialize submodules (`fzf-git.sh` and tmux's plugin manager, TPM):

    ```bash
    git submodule update --init
    ```

3. Create real directories for tools that mix authored config with local state, then Stow into `$HOME`:

    ```bash
    mkdir -p ~/.config/herdr ~/.config/jiratui ~/.config/pi/agent/extensions
    stow -t ~ .
    ```

    `.stow-local-ignore` keeps `.git`, `.gitignore`, `.DS_Store`, `platforms/`, and the root `README.md`/`AGENTS.md`/`package-lock.json` out of the link; those stay in the repo instead of linking into `$HOME`.

4. If `~/.config/<tool>` already exists as a real directory before you stow, rather than being created fresh by Stow, Stow folds into it and links files individually instead of linking the whole directory. That's expected, and it's exactly what happens with `~/.config/pi/agent`—see below.

## Mac terminal workflow

Install Herdr with `brew install herdr` and Kitty with `brew install --cask kitty`. AeroSpace's Hyper+T shortcut opens Kitty, which initializes the normal zsh environment and attaches to Herdr. There is no Herdr autostart in `.zshrc`, so inner panes and ordinary WezTerm/tmux shells remain usable. For a recovery shell without Herdr, run `kitty /bin/zsh -l` or open WezTerm.

Kitty discards inherited Herdr/tmux/WezTerm pane IDs before launching its client, so opening it from another terminal does not become a nested multiplexer. The Mac Kitty settings retain MesloLGS Nerd Font Mono at 14pt, 0.93 background opacity, and blur 10. Kitty's native `*-theme.auto.conf` files follow macOS appearance with our exact Everforest palettes—no additional watcher is needed. Option acts as Alt; application-owned modified keys are not consumed for Kitty font/fullscreen actions. Remote control is local-socket-only.

Herdr's platform-neutral config lives at `.config/herdr/config.toml`. The old overlay path is a compatibility symlink so an existing Linux deployment keeps working before the next `link.sh` run. Both platforms use the same bindings and sidebar: Ctrl+B is the prefix, `%`/`"` split right/down, arrow keys move focus after the prefix, `c` creates a tab, and `d` detaches. WezTerm/tmux remain unchanged fallbacks; inner tmux retains precedence in the shared Neovim adapters.

Keep `~/.config/herdr` real and link only the authored config/plugin; sessions, logs, and sockets must stay outside Git. Register the shared last-focus plugin once with `herdr plugin link ~/.dotfiles/.config/herdr/lastfocus`. It supplies Ctrl+B then `;`, `l`, or `L` for tmux-style last pane, tab, or workspace; see [its setup notes](.config/herdr/lastfocus/README.md) to start the recorder without restarting an existing server. After editing config, use `herdr server reload-config` and `aerospace reload-config --no-gui`; neither requires stopping sessions.

Run parser/deployment checks with Kitty's bundled Python and the live isolated Herdr regression:

```bash
uv run --offline --no-project --python ~/.local/share/uv/tools/ipython/bin/python \
    kitty +runpy 'import runpy; runpy.run_path("tests/test_mac_terminal.py", run_name="__main__")'
TMPDIR=/tmp node platforms/omarchy/tests/test_herdr_port.mjs
```

The Herdr test uses a private server and synthetic input, never real agent prompts or existing panes. Actual graphics resize/reattach behavior still needs a visual workflow check.

## pi agent config

`~/.config/pi/agent` mixes stowed config (`AGENTS.md`, `extensions/`, `models.json`, `settings.json`, `skills/`) with files pi manages itself (`auth.json`, `sessions/`, `npm/`, `git/`). Those four are gitignored and intentionally not part of this repo: `npm/` and `git/` are pi's own package install/clone directories for whatever's listed in `settings.json`'s `packages` array, and `auth.json`/`sessions/` hold credentials and session history that shouldn't be shared across machines.

On a genuinely fresh machine, no manual step is needed for `npm/`/`git/`: just launch pi (or run `pi list`) after stowing, and it reads the already-stowed `settings.json` and installs any missing `packages` entries into fresh local directories automatically.

For Herdr's official lifecycle/session integration, keep `~/.config/pi/agent/extensions` a **real directory** with individual authored links inside it, then run `PI_CODING_AGENT_DIR="$HOME/.config/pi/agent" herdr integration install pi`. The generated `herdr-agent-state.ts` belongs only in that local directory, never in this repository. If `extensions` is currently a directory symlink into the checkout, move that symlink into a local backup, create the real directory, and rerun Stow before installing the hook. Existing Pi sessions need `/reload`; new sessions discover it automatically. The Mac's existing theme-following package remains unchanged.

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

## JiraTUI

Install with `uv tool install jiratui`, then open a new zsh shell (or run `source ~/.zshrc`). The `jiratui` wrapper uses that tool's Python environment to register our Everforest themes before starting the upstream CLI. Run `jiratui ui`; the theme follows `~/.cache/appearance`, while an explicit `--theme` or a non-Everforest config preference disables automatic following.

Keep credentials only in `~/.config/jiratui/secrets.env` with mode `0600`, never in `config.yaml`. The launcher loads that file without overriding exported environment variables; the repository ignores it. The tracked config contains the Jira server URL but no credentials.

Run the isolated wrapper tests using the installed tool environment:

```bash
uv run --offline --no-project --python ~/.local/share/uv/tools/jiratui/bin/python \
    ~/.local/share/uv/tools/jiratui/bin/python -m unittest discover \
    -s tests -p test_jiratui_launcher.py -v
```

## Other first-launch steps

- **Neovim**: uses the built-in `vim.pack` plugin manager; plugins install automatically the first time you launch `nvim`.
- **tmux**: plugins install via TPM; press `prefix + I` inside tmux on first use. `.config/tmux/plugins/*` other than `tpm` itself is gitignored—TPM installs the rest at runtime, they're not vendored here.

See `AGENTS.md` for more detail on the repo's structure and conventions.
