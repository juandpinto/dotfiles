# Omarchy / Asahi overlay

This is an incremental dual-OS migration, not an invitation to Stow the Mac
package onto Linux. Keep one `main` branch. The legacy root layout remains the
Mac deployment; this overlay contains Linux-only files. Shared Neovim and
IPython live at their existing root paths. No remote push or commit is part of
the migration.

## What is linked

- Shared: `.config/nvim`, `.config/shell`, `.config/stylua`, `.config/ruff`, `.config/yazi`, `.config/herdr/config.toml`, `.markdownlint.jsonc`, and the explicitly tracked IPython config/startup files (never its runtime dir).
- Linux-only: the files below `platforms/omarchy/home/`, selectively linked by
  `link.sh`.
- Private: the four mail account configs (`aerc/accounts.conf`, `isyncrc`, `msmtp/config`, `notmuch/default/config`) carry email addresses and logins, so they live in the private companion repo at `~/.dotfiles-private` (override with `DOTFILES_PRIVATE_DIR`), laid out as `omarchy/home/...` exactly like this overlay. `link.sh` links them when that repo is present and skips them otherwise. The public `.gitignore` blocks those paths so they cannot be re-added here by accident.
- **Do not run `stow -t ~ .` at the repo root on Linux.** The Mac package also
  includes AeroSpace, Karabiner, Sketchybar, launchd, and macOS-only startup code.
- `platforms/` is excluded from the root Stow package, preserving the existing
  Mac workflow. A later package reorganization can be a separate reviewed change.

Both machines use `~/.dotfiles`. New Linux code uses `$DOTFILES_DIR` (default `~/.dotfiles`) and relative links, not a username. If the checkout moves, update that variable in the Linux Bash entry point and rerun the linker. Existing shells that retain the old `~/dotfiles` value normalize it when we source `.bashrc`.

## Deploy / dependencies

```bash
omarchy pkg add kitty yazi
git submodule update --init .config/zsh/plugins/fzf-git.sh
./platforms/omarchy/link.sh
~/.local/bin/everforest dark
hyprctl reload
hyprctl configerrors
nvim
uv tool install ipython --with matplotlib --with pandas --with numpy
```

Neovim needs 0.12+, Git/make/a C compiler, ImageMagick, and the existing native
build tools. The pinned Jupynvim release has no Linux ARM64 download; its
existing build hook falls back to Cargo successfully. Language tools remain
Mason-managed. `markdownlint` and Prettier are automatically installed for the shared Markdown lint/format configuration; the home-directory `.markdownlint.jsonc` link preserves the Mac rules. `:Copilot auth` is a per-machine action; credentials are not copied.

`link.sh` backs up replaced paths under
`~/.local/state/dotfiles-migration/backups/`. It never touches package-owned
Omarchy files. Theme **directories**, rather than individual palette files,
are linked: Omarchy copies palettes into a differently nested staging directory,
where an individually linked relative `colors.toml` would become broken.
Templates and hooks can safely be file links. `~/.config/kanata` is also one directory link so the keymaps, guard daemons, tests and `kanata-install-system`'s staging copies stay together. Everything else is linked file by file (skipping `__pycache__`), so real directories like `~/.config/aerc`, `~/.config/hypr` and `~/.local/share/applications` can mix our links with Omarchy-managed files.

## Fresh machine checklist

What a new Omarchy install needs beyond `link.sh`, in order. Items marked *system* need `sudo` and are deliberately not automated.

1. Clone both repos and link: `git clone https://github.com/juandpinto/dotfiles.git ~/.dotfiles`, `git clone <private-remote> ~/.dotfiles-private && chmod 700 ~/.dotfiles-private`, `git -C ~/.dotfiles submodule update --init .config/zsh/plugins/fzf-git.sh`, then `~/.dotfiles/platforms/omarchy/link.sh`.
2. Git identity: `git config --global user.name` / `user.email` (Omarchy's `~/.config/git/config` has aliases and the `gh` credential helper but no identity).
3. Packages: `omarchy pkg add kitty yazi aerc isync msmtp notmuch w3m trash-cli` and `kanata` from the AUR (`omarchy pkg add kanata` resolves it; 1.12.0 was used here); `mise install` (the linked `~/.config/mise/config.toml` lists codex, gh, node, pi, python); `uv tool install ipython --with matplotlib --with pandas --with numpy`.
4. Keyboard and Touch Bar (*system*): `kanata-install-system` copies the reviewed keymaps and root service from `~/.config/kanata/system/` into `/etc/kanata` and `/etc/systemd/system`, then `systemctl --user enable --now kanata-palm-guard.service`. Read `~/.config/kanata/README.md` first; it documents the emergency exit (hold Left Control + Space + Escape). Then build, install and pin the patched tiny-dfr (see [Touch Bar](#touch-bar)).
5. Desktop: `everforest dark`, `hyprctl reload`, `hyprctl configerrors`. Third-party shell plugins, each via `omarchy plugin add <url> --enable`: [keystroke](https://github.com/evindor/keystroke), [omarchy-expose](https://github.com/kristofferR/omarchy-expose), [fathom](https://github.com/mtolhuys/fathom), [cursor-accent](https://github.com/SmoothPixels/cursor-accent), [omarchy-herdr](https://github.com/jankeesvw/omarchy-herdr), [omarchy-notification-center](https://github.com/jankeesvw/omarchy-notification-center), [omdrop](https://github.com/netmojo-systems/omdrop-plugin), [omamail](https://github.com/huacnlee/omamail), [omarchy-workspace-icons](https://github.com/woodenplastic/omarchy-workspace-icons). Then our own plugins: `omarchy plugin enable` each of `jdpinto.background`, `jdpinto.lock`, `jdpinto.herdr`, `jdpinto.lid-awake` and `jdpinto.charge-limit` (then `omarchy bar move jdpinto.lid-awake --after omarchy.indicators` and `omarchy bar move jdpinto.charge-limit --after jdpinto.lid-awake`), `build-island-bar`, `bar-app-glyphs apply` (see [bar.md](bar.md)), and `omarchy plugin disable omarchy.flush-bar`.
6. Apps: Yazi as the file manager (`update-desktop-database ~/.local/share/applications` and `xdg-mime default yazi.desktop inode/directory`; see [File manager](#file-manager)); Herdr, then `herdr integration install pi`; the linked `~/.local/share/applications/*.desktop` web-app launchers also need `xdg-mime default Slack.desktop x-scheme-handler/slack` so `slack-webapp-handler` catches sign-in deep links; aerc as the mail client with `xdg-mime default aerc-open.desktop x-scheme-handler/mailto` (see [Default mail client](mail.md#default-mail-client)).
7. Timers: `systemctl --user daemon-reload && systemctl --user enable --now mailsync.timer pi-copilot-usage.timer wallpaper-shuffle.timer trash-empty.timer` (mail first needs the secrets and the manual initial `mbsync -a`; see [mail.md](mail.md)). Wallpapers live in `~/Documents/backgrounds`, outside Git.
8. Per-machine, never linked: `~/.config/hypr/monitors.lua` (display scale), `~/.config/omarchy/shell.json` (GUI-managed plugin/bar state), Pi `/login`, `:Copilot auth`, Tailscale, 1Password.

## Bash

The Linux `.bashrc` loads Omarchy's maintained foundation once, then the personal
Bash additions: theme-aware eza `ls`, fd-backed fzf previews/completion, fzf Git
widgets, `y` (Yazi + change directory), `lg`, prefix-history search, Alt-arrow
word movement, pane titles/CWD, and prompt markers. mise, Starship and zoxide are
not initialized twice. NVM/Homebrew paths and the Mac's Pi agent directory are
not imported. Existing shell sessions need `source ~/.bashrc` or a new terminal.

## tmux

Ctrl+B is primary; there is no secondary prefix and no Omarchy Alt-number,
Alt-Enter, Alt-Escape, or Ctrl+Alt-arrow bindings. Native command keys are
unchanged except `%`, `"`, and `c` also inherit the current pane directory.
The Mac's personal vi copy-mode feel (`v`/`y`, half-page movement, prompt jumps)
is retained with `wl-copy`, not `pbcopy`. Copy stays in copy mode until `q`.
Focus events, true colour, extended keys, clipboard support and graphics
passthrough remain. No TPM/theme/plugin framework is required here.

The pane-title border appears in multi-pane windows, keeping the existing
IPython execution timer useful. Theme changes reload only palette settings,
not key tables. No running user server was killed during configuration.

## Herdr trial

Herdr now has an official managed Pi hook, Pi conversation titles in the sidebar, a thin default-terminal wrapper for the upstream bar widget, and shared Neovim Slime/Sidekick adapters. Inner tmux keeps priority, preserving the Mac workflow. Herdr processes remain independent of the editor; only its config file is linked, never runtime state. The config and two plugins are shared with the Mac from `.config/herdr/`: `lastfocus` (tmux's `prefix+;`, `prefix+l`, `prefix+L`; see [its README](../../.config/herdr/lastfocus/README.md)) and `labels` (sidebar numbers for the `prefix+{`/`prefix+}`/`prefix+alt+1..9` agent shortcuts, pi titles without the `π`, and tmux-style automatic tab names; see [its README](../../.config/herdr/labels/README.md)). See [Herdr trial and desktop integration](herdr-trial.md) for controls, verification, startup/reload requirements and rollback boundaries.

## Kitty and data science

Kitty is first in `~/.config/xdg-terminals.list`; Foot remains a recovery fallback.
The installed JetBrainsMono Nerd Font and Omarchy's 9pt size are retained for
now. Background opacity is **0.93**, matching the WezTerm configuration; the
foreground text is not made transparent by Kitty. Kitty requests a small background blur; Hyprland enables a gentle blur only for Kitty/Herdr terminal windows, retaining other apps' prior behavior and the existing opacity policy. Kitty runs natively on Wayland.

Native shell integration, modified-key passthrough and a local-only control
socket are configured. No in-band terminal escape can invoke Kitty remote
control (`socket-only`). No tmux autostart is imposed.

The persistent REPL workflow stays the same: start IPython in a tmux pane and
send cells with vim-slime. Notebook editing uses the existing Jupynvim setup.
`show_fig` now uses `kitten icat --passthrough=tmux --transfer-mode=stream` in
Kitty/tmux; this implies Unicode placeholder images rather than the old raw
absolute-position sender. No new matplotlib backend package is required.
ImageMagick CLI handles image.nvim, so no architecture-specific Lua rock is
needed. Image setup is deferred in headless Neovim until a UI attaches.

The original WezTerm/Sixel path remains for Macs not using Kitty. `preview=True`
opens macOS Preview or Linux's default image viewer. `show_html` still opens
DataFrames as HTML in the browser. Queued-cell paste safeguards, output boxing,
and the execution timer are unchanged.

Over SSH the remote machine needs the helper and `kitten`; stream transfer
avoids local-file/shared-memory assumptions. If terminal detection is lost,
`NVIM_FIGURE_BACKEND=kitty` opts in. The remote tmux also needs passthrough.
Images still belong to the GUI: reattaching in a new terminal may require
rerendering a plot. Validate resize/scroll/detach with real work before assuming
perfect graphics persistence.

## Everforest only

```bash
everforest          # toggle
everforest dark
everforest light
everforest status
```

**Super+Ctrl+Shift+Space** now toggles Everforest dark/light instead of opening
the full theme picker. With the accepted SpaceFN policy, use a quick Space tap.
The full picker is still available with `omarchy theme switcher`. The Omarchy
menu also has searchable Everforest toggle/dark/light actions.

The user palettes use sainnhe/everforest **medium** contrast, including light
background `#fdf6e3`. They are user overlays; no stock theme is edited. The
command keeps the current wallpaper and lets Omarchy retint its supported apps.
Generated Starship and tmux palettes follow the same selection. The theme-set
hook writes `~/.cache/appearance` atomically, preserving the Mac's shared-state
contract for Neovim, eza, and IPython. No Linux appearance polling daemon.
Running Neovim follows its existing focus/timer logic; IPython syntax theme is
selected at session startup (restart an existing REPL to change that palette).

Pi follows the same hook through a fixed generated `everforest-omarchy` theme, preserving our custom Pi palettes while avoiding Herdr's terminal appearance-report race. Run `/reload` once after adopting that setting; later light/dark toggles hot-reload the running UI. No additional watcher or extension is installed. See [Pi appearance details and rollback](pi-migration.md#omarchy-driven-appearance).

## Bar and workspace icons

We keep Omarchy's bar engine, with Workspace Icons supplying numbered tiles, window counts, and the Mac bar's look: the same monochrome sketchybar-app-font glyphs for our apps (with matching Material Design icons for Linux-only apps and for programs running in Kitty), each workspace in its own Everforest color with a filled tile when focused, the focused app's name in muted text after the workspaces, a now-playing widget, and one floating island in the terminal's translucent material, all following dark/light switches. The island's gaps and corner radius are live settings in `shell.toml`, and it comes from a small overlay regenerated onto the installed engine after every Omarchy update, not a frozen copy. Omarchy's flush-bar service is disabled so `looknfeel.lua` controls the window gap below the bar. Per-widget colors on the right remain deferred. See [bar setup, plugin patches, glyph mapping, verification, and rollback](bar.md) before updating the plugin.

## Pi/Copilot usage monitoring

`pi-copilot-usage.timer` feeds the existing `omarchy.agents` widget every five minutes during the desktop session. We show local Pi/Copilot tokens by day and model, plus Copilot's account-wide monthly premium allowance and reset date. Only entries explicitly attributed to `github-copilot` are counted; copied fork/clone history is deduplicated, and cached/reasoning tokens are not counted twice. Unattributed summary/tool usage is excluded. API calls are not labeled as user prompts, and token counts are not converted into billed requests or charges.

The collector reads Pi's existing GitHub OAuth credential in memory and makes a read-only request to GitHub's internal Copilot account endpoint. It never refreshes or rewrites credentials, follows redirects with them, runs secret-manager commands, or logs credential/response contents. The private, atomically written `~/.local/state/omarchy/agents/usage/copilot.json` contains only derived usage metadata. If authentication, connectivity, or the undocumented endpoint fails, local token charts remain available and the panel reports the allowance as unavailable rather than inventing a value. No package-owned Omarchy file is changed.

After linking the overlay, run `systemctl --user daemon-reload` and `systemctl --user enable --now pi-copilot-usage.timer`. Run `systemctl --user start pi-copilot-usage.service` for an immediate update; the widget's normal refresh only invokes Omarchy's packaged collectors. On first installation, `omarchy shell omarchy.agents refresh` makes the widget discover the additional record without restarting the shell. Stop future updates with `systemctl --user disable --now pi-copilot-usage.timer`; the last saved record remains until removed or hidden through the widget's provider settings.

The standard Pi agent/session paths are used, with `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR` honored when supplied to the service. Tests use synthetic sessions and mocked HTTP, never real credentials: `uv run --offline --no-project --python /usr/bin/python3 -m unittest discover -s platforms/omarchy/tests -p 'test_pi_copilot_usage.py' -v`.

## Trash instead of `rm -rf`

Pi's shared `guard-destructive` extension blocks the agent's `rm -rf` on anything that isn't recognizably disposable (build artifacts, OS temp dirs, anything inside a directory named `tmp`, or a path that doesn't exist yet) and tells it to use `trash <path>` instead, which is recoverable. Only `PI_PERMANENT_DELETE=1 rm -rf <path>`, which the agent is instructed to use after asking in conversation, reaches an interactive confirm. On Linux `trash` comes from `trash-cli` and writes to the standard `~/.local/share/Trash`, the same place `gio trash` and the desktop file managers use. `trash-empty.timer` runs `trash-empty 30` daily, deleting only entries trashed more than 30 days ago. On the Mac, `trash` is macOS's own (14+, otherwise `brew install trash`) and uses Finder's Trash; the equivalent 30-day cleanup is Finder's own setting (Settings → Advanced → "Remove items from the Trash after 30 days"), so no launchd job is needed there.

The guard's string rules are unit-tested with `node .config/pi/agent/extensions/guard-destructive/rules.test.mjs`.

## Wallpaper shuffle

`wallpaper-shuffle.timer` selects a random image from `~/Documents/backgrounds` at desktop login and every minute thereafter, avoiding an immediate repeat. We use `omarchy theme bg set`, keeping the native background renderer and transitions; no wallpaper daemon, theme-colour change or stock-file edit is involved. The folder is rescanned on each run, so newly added JPG/JPEG/PNG/GIF/BMP/WebP files are picked up automatically. Only files directly in that folder are included; images stay outside Git.

After linking the overlay, enable it with `systemctl --user enable --now wallpaper-shuffle.timer`. Pause it with `systemctl --user stop wallpaper-shuffle.timer`, or remove automatic startup with `systemctl --user disable --now wallpaper-shuffle.timer`. Run `wallpaper-shuffle` for a new random image immediately. Everforest's light/dark helper already preserves the wallpaper; another full theme selection can replace it until the next shuffle.

The helper and systemd units live in this Linux overlay; the Mac setup is unchanged. Run `bash platforms/omarchy/tests/test_wallpaper_shuffle.sh` for isolated checks that never touch the desktop.

For a subtle 1-second crossfade instead of the stock diagonal reveal, the user-owned `jdpinto.background` clone lives under `home/.config/omarchy/plugins/` and is linked as a complete directory. Activate it with `omarchy plugin enable jdpinto.background`; the current shell's cached QML may require `omarchy restart shell` after approval to apply code changes reliably. Disable the clone with `omarchy plugin disable jdpinto.background` to restore the stock renderer. See the clone's README for provenance and update caveats; no package-owned file is patched.

## Logo and screensaver

Our jdp monogram replaces Omarchy's logo in fastfetch and the About window (`home/.config/omarchy/branding/about.txt`) and as the bar's menu button (see [bar.md](bar.md)). It is j, d and p sharing one stem and one bowl: the j's stem is the p's, the p's bowl is the d's, and the d's own stem stands to the right. It leans 12°, the d's tip and the j's hook are cut at 45°, and the p is the theme's green. The bar module's two paths are the source drawing; `tests/rasterize-mark.mjs` turns them into the block text. Favicon tiles made from the same paths (cream with the p in Everforest light's green for light pages, dark with the green p for dark ones, and one SVG that switches with `prefers-color-scheme`) are in `~/Documents/logo-drafts/final/`, outside Git.

The screensaver animates it. An Omarchy (`ttfx`) effect assembles the monogram. The monogram splits into j, d and p while i, n, t and o slide out from behind the p. A rainbow of the bar's seven workspace colors washes across the seven letters of "jdpinto" and back. Another random effect rebuilds the word, and it folds back into the monogram. The effects receive our frames as colored text (`--existing-color-handling always`), so each one ends exactly where our next frame starts. Colors come from the current theme.

Omarchy has no setting for the screensaver program. Its launcher runs `kitty -e omarchy-screensaver`, and Hyprland puts Omarchy's own `bin` first in `PATH`, so a copy in `~/.local/bin` is never found. Kitty searches `exe_search_path` before `PATH` for programs it starts by name, so `kitty.conf` points it at `home/.config/kitty/exe-overrides/`, which holds only our `omarchy-screensaver`. It keeps the stock script's contract: black background, hidden cursor, and a key or lost focus ends it and closes every screensaver window. It also sets its own Kitty window to full opacity, since `kitty.conf`'s `background_opacity` would otherwise let the wallpaper show faintly through the black. It does not follow upstream changes to the stock script, and it only applies while Kitty is the default terminal. To return to the stock screensaver, remove the `exe_search_path` line; the next screensaver picks that up.

Like the stock screensaver, it exits when it loses focus. Because Omarchy enables Hyprland's `focus_on_activate`, a terminal that requests attention (for example, an agent session sending a notification) takes focus and ends it.

`omarchy-screensaver --preview` runs the animation in any terminal, and any key exits. Run `bash platforms/omarchy/tests/test_screensaver.sh` for isolated checks that take about a minute: the letters carry the bar monogram's geometry, and in a private tmux server every stage lands exactly on our frames.

## File manager

Yazi replaces both Nautilus (Omarchy's default) and Strata (used here before). The configuration in `.config/yazi` is shared with the Mac. Yazi runs in a kitty window with the app ID `org.omarchy.yazi`, so it gets Omarchy's terminal window rules. On Linux, it is the file manager in three places:

- **Keys:** `Super+Shift+F` opens Yazi. `Super+Alt+Shift+F` opens it in the focused terminal's directory (`bindings.lua`).
- **Folders opened by other apps** (`xdg-open`, `inode/directory`): our `yazi.desktop` replaces the packaged one. It starts a uwsm *service*, not the default scope, because `xdg-open` waits for its handler and would otherwise block until Yazi quits.
- **"Show in folder"** from browsers and Electron apps (`org.freedesktop.FileManager1` on D-Bus): `yazi-filemanager1.py` opens Yazi with the file selected. Its service file in `~/.local/share/dbus-1/services/` takes priority over Nautilus's system-wide one. Strata's installer adds a competing `io.github.lgse.Strata.FileManager1.service` there. Remove it if a Strata reinstall brings it back.

Open and save dialogs are a separate xdg-desktop-portal FileChooser setting (`~/.config/xdg-desktop-portal/hyprland-portals.conf`). They still use Strata, which is not removed by this setup.

Shared plugins and keys (`keymap.toml`, `init.lua`): `M` mounts, unmounts or ejects drives (`mount`, using `udisksctl`). `T` maximizes or restores the preview (`toggle-pane`). `c` `m` changes permissions of the selected files (`chmod`). `term-cwd` reports Yazi's directory to the terminal through OSC 7. `t` `h` opens a new Herdr tab in Yazi's directory (`herdr-tab-here`): inside Herdr, in the same workspace. From a standalone Yazi window, it uses Herdr's focused workspace and then raises Herdr's window, or opens one (through `jankeesvw.herdr`'s window discovery and `herdr-widget-open`). On the Mac, the key falls back to a plain `herdr tab create`. `package.toml` pins them, and `git` (the Git status signs), at upstream `4dc7f1b` ("types for v26.9.1"). Plugin versions must match Yazi's: the older `git` pin used the fetcher API from before 26.8.15, so its tasks never finished and every quit asked to confirm. Don't run `ya pkg upgrade` until Yazi itself is newer than 26.9.1: mount's next commit uses a newer API. `ya pkg` rewrites `package.toml` and drops comments, so this note lives here.

## Lid awake

Omarchy's Stay Awake (`Super+Ctrl+I`) only stops the idle screensaver, lock and display-off while the lid is open; closing the lid still suspends. `lid-awake` is the separate lid-closed switch, so agents keep running in a closed laptop:

- `lid-awake on|off|toggle|status`, `Super+Ctrl+Shift+I`, and a laptop icon in the bar after the indicators while it is on (click it to turn off).
- While on, a closed lid still locks and blanks the display, but does not suspend. On AC it stays awake indefinitely.
- It suspends anyway when closed and either on battery at 20% or with the battery at 45 °C, which catches a laptop packed into a bag. The system's own critical-battery suspend remains as a backstop.
- A docked lid close (external monitor) is left to Omarchy's clamshell mode; no guards apply.
- It is off after every reboot.

`lid-awake.service` holds a logind `handle-lid-switch` inhibitor around `lid-awake watch`, which checks every 30 s and logs each closed period, including the hottest battery reading, to `journalctl --user -u lid-awake`. Thresholds are the `LID_AWAKE_*` defaults at the top of the script. No logind, UPower or package-owned file is changed. After linking, run `systemctl --user daemon-reload`, `omarchy plugin enable jdpinto.lid-awake` and `omarchy bar move jdpinto.lid-awake --after omarchy.indicators`. Run `bash platforms/omarchy/tests/test_lid_awake.sh` for isolated checks with mocked logind, systemd and batteries.

Overnight on AC, Omarchy's `omarchy battery charge limit 80` keeps the battery at 80% (charging resumes below 75%) instead of holding it full and warm; `omarchy battery charge limit 100` restores full charging. It needs sudo, and Asahi keeps the setting across reboots. The `jdpinto.charge-limit` bar icon (a battery with a heart) shows while the limit is below 100% as a reminder; clicking it opens a terminal that sets it back to 100%.

## Touch Bar

tiny-dfr, the Touch Bar daemon, sets the bar's backlight to 0 after 60 s without input and whenever the lid is closed. This MacBook's panel flashes white at 0, often about once a second, whether or not the screen is on ([tiny-dfr#32](https://github.com/AsahiLinux/tiny-dfr/issues/32); not fixed in 0.3.8). It doesn't flash at the dimmed brightness 1. `packages/tiny-dfr/` rebuilds `asahi-alarm`'s package (0.3.7 with their `81.patch`, same build steps) plus our `idle-blank.patch`: an idle bar stays at brightness 1 and is painted black instead, so it still looks off, and black OLED pixels are unlit, so it doesn't age the panel. A closed lid gets the same treatment, because with [lid awake](#lid-awake) or a docked display the laptop can run for hours with the bar flashing unseen under the lid. As before, the first touch on a dark bar only wakes it, and opening the lid wakes it too. Our build is version `0.3.7-1.2`, so `pacman -Q tiny-dfr` shows which one is installed.

Build, install and pin (*system*):

```bash
cd ~/.dotfiles/platforms/omarchy/packages/tiny-dfr
makepkg -f   # needs the rust package; build output is gitignored
sudo pacman -U tiny-dfr-0.3.7-1.2-aarch64.pkg.tar.xz
grep -q '^IgnorePkg.*tiny-dfr' /etc/pacman.conf || sudo sed -i '/^\[options\]/a IgnorePkg   = tiny-dfr' /etc/pacman.conf
sudo systemctl restart tiny-dfr
```

`IgnorePkg` stops updates replacing our build; Omarchy's updater respects it, and its migrations edit `pacman.conf` in place, so the line survives them. When `pacman -Syu` warns that it is ignoring a newer tiny-dfr, check #32: if upstream has fixed the flashing, remove the line and install theirs; otherwise copy their new `PKGBUILD` here, keep our `pkgrel` suffix, patch and checksums, and rebuild. To go back to the stock package, remove the `IgnorePkg` line, run `sudo pacman -S tiny-dfr` and restart the service.

## Mail

aerc + mbsync + msmtp + notmuch, with gnome-keyring (`secret-tool`) for the two app passwords and a `mailsync.timer` systemd user timer instead of launchd. The four account configs (no secrets, but addresses and logins) are tracked in the private companion repo; keybindings, stylesets and the sync/filing helpers are shared with the Mac. Stock Arch aerc, no local build. Setup order matters (store secrets, run the initial `mbsync -a` by hand, then enable the timer): see [mail.md](mail.md); search semantics are in [mail-search.md](mail-search.md); the recovered Mac history is `Archive/mail-setup-macos.md`.

```bash
omarchy pkg add aerc isync msmtp notmuch w3m
git clone <private-remote> ~/.dotfiles-private && chmod 700 ~/.dotfiles-private
./platforms/omarchy/link.sh
secret-tool store --label='Mail: iCloud app password' mail-account icloud
secret-tool store --label='Mail: Gmail app password' mail-account gmail
mbsync -a; mbsync -a; notmuch new   # see mail.md: do not &&-chain the first run
systemctl --user daemon-reload && systemctl --user enable --now mailsync.timer
```

## Neovim: small native additions and optional recommendations

Already present: which-key, Telescope, Gitsigns, completion, mini.ai/surround,
project sessions/recent files, large-file handling, formatter/LSP plumbing,
notebooks, wiki support and inline images. Do not duplicate these with Snacks,
Flash, Persistence or another statusline just because LazyVim uses them.

Adopted from LazyVim: native autocmds restore the last cursor position in ordinary files, run `checktime` on focus/terminal return, and close help/diagnostic utility windows with buffer-local `q`. Which-key's existing window-hydra is on `Ctrl+W`, then `Space`; Escape leaves it. No new plugin was added. The handlers are in `lua/juan/autocmds.lua`; the hydra mapping is in `plugins/which-key.lua`.

Still optional: grug-far for previewable project-wide search/replace, useful for research code and Markdown/wiki work. Native quickfix + `:cdo` remains the lean alternative. Trouble is optional for larger codebases; we can start with the existing Telescope diagnostics and native quickfix.

The port adds only optional Omarchy clipboard integration (the maintained
packaged provider, not LazyVim) and safe first-run/headless appearance/image
handling. Plugin pins are unchanged. An independent old profile is preserved:

```bash
NVIM_APPNAME=nvim-lazyvim nvim
```

## Verification / recovery

Verified during migration:

- Native Neovim starts with Everforest and without loading lazy.nvim.
- A synthetic notebook initializes the built ARM64 backend (no cell executed).
- Telescope's native fzf module loads; ty is installed.
- The tmux command key table differs from stock only by same-directory actions.
- Kitty parses opacity 0.93 / socket-only control and launches on Wayland.
- A real Kitty/tmux matplotlib test negotiated stream graphics and put 175
  Unicode placeholder cells into the tmux grid; rendering exited successfully.
- Eight Python renderer-routing tests pass without GUI actions.
- Everforest light/dark round trip updated palettes/state correctly and restored
  dark mode. Hyprland reports no config errors; Kanata/guard remain active.

Tests:

```bash
~/.local/share/uv/tools/ipython/bin/python -m unittest discover \
  -s platforms/omarchy/tests -p 'test_*.py' -v
```

Local logs, synthetic fixtures, and backup pointers are under
`~/.local/state/dotfiles-migration/`, outside Git. The original baseline backup
path is in `backup-path`; subsequent replaced links are recorded separately.
To roll back a linked file, remove **only its symlink** and restore the matching
backup. Do not reset Omarchy wholesale or kill real tmux sessions. The accepted
Kanata timings, keyboard service and palm safeguard were not changed.

Launcher research: the marketplace's [Omarchy Launcher](https://github.com/hominluo/omarchy-launcher)
(version 1.0.3 when reviewed) is the closest native Alfred/Raycast-style candidate
(scripts, quicklinks, files/content, calculator, snippets and stock menu integration).
[Vicinae](https://github.com/vicinaehq/vicinae) is a broader independent alternative;
[Omarchy Files](https://github.com/crmne/omarchy-files) +
[Web Launcher](https://github.com/greenspotmail/omarchy-weblauncher) are smaller
purpose-built plugins.
See the [thorough Keystroke comparison](launcher-comparison.md) for the newer shortlist and local ARM64 test results, and [Pi migration notes](pi-migration.md) for the installed personal skills/extensions. No third-party launcher was installed or bound by this migration. Review source
and test built-ins alongside the stock launcher before enabling extensions;
plugins/extensions execute as the desktop user without a security sandbox.
