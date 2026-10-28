# Bar and workspace icons

We keep Omarchy's stock Quickshell bar engine and its existing widgets. This brings over the Mac bar's workspace/app overview, its monochrome app glyphs, its per-workspace Everforest colors, a floating island, and translucent surfaces without installing Waybar or editing package-owned files. Per-widget colors on the right side remain deferred: Omarchy's widgets all draw in one bar text color, and recoloring them would mean cloning each package-owned widget.

## Current appearance

- **One floating island** spanning the bar, in the same translucent material as Kitty: the themed background at Kitty's 93% `background_opacity`, the same compositor blur, and a faint accent border. Its gap to the top of the screen, gap to the sides, and corner radius are [settings](#settings), by default 4, 8 (aligned with the windows' side gaps), and 10 logical pixels. Text and icons are not made transparent with the background.
- Existing Everforest dark/light palettes supply all colors. We do not pin background, text, or accent hex values in the shell override.
- A targeted `^omarchy-bar$` layer rule enables the existing gentle compositor blur (`size = 4`, `passes = 2`). The rule ignores pixels with alpha at or below 0.2, so the fully transparent background toggle does not blur the empty strip.
- **Our jdp monogram as the menu button**, in place of Omarchy's logo: j, d and p sharing one stem and one bowl, leaning 12°, with 45° cuts on the d's tip and the j's hook; the p in the theme's green, the rest in the bar text color. The same drawing is the About/fastfetch logo (`branding/about.txt`). A custom module, `jdp-menu`, stands in for Keystroke's own bar button (the Omarchy font glyph) with the same clicks: left toggles the Keystroke palette, right opens a terminal, and the palette's bar items, such as a running timer, still follow it.
- [Workspace Icons](https://github.com/woodenplastic/omarchy-workspace-icons) replaces the stock workspace-number widget. Rounded tiles show numbers and up to three app icons; only the workspace you're on has a filled tile, and the others sit on the island itself until hovered. Each window gets its own icon, in window order, as on the Mac, so two terminals show two terminal icons; past three icons the rest are summarized as `+N`.
- **Rainbow workspaces**, as on the Mac: workspace 1 is red, then orange, yellow, green, cyan, blue, and magenta from 7 on, read live from the current theme's `colors.toml`. The focused tile is filled with its color and its number and icons take the contrasting background color; other tiles show their number and icons in their color.
- **Monochrome app glyphs**, drawn exactly in the workspace color. Apps the Mac bar knows use its [sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) artwork, so they look the same on both machines. Linux-only apps and terminal tools without a fitting glyph there use [Material Design Icons](https://pictogrammers.com/library/mdi/) in the same filled style (a folder for Files, a pen for Xournal++, π for Pi), and HEY uses its [Simple Icons](https://simpleicons.org/) logo. Programs running in Kitty, such as aerc, Herdr, and Neovim, show their own glyph instead of the Kitty cat. Unmapped apps keep their desktop icon, tinted; most launcher icons are full tiles, which tint to a solid square, so new apps are worth mapping.
- **The focused app's name** after the workspaces, in the theme's muted color, as the Mac's `front_app`: the desktop entry name ("kitty", "Brave Origin"), or a web app's launcher name ("YouTube"), with the window title as tooltip. This is a 70-line custom bar module, not a plugin.
- **Now playing** (`omarchy.media`, MPRIS with transport buttons) at the start of the right section, hidden while nothing plays, like the Mac's `♫` item.
- Empty inactive workspaces and special workspaces are hidden. Workspace previews are off; Exposé and Fathom remain available.
- The clock is at the far right. Other widgets, clock formats, idle settings, and services are preserved.

`bar.transparent` stays `false`: with the island bar, Omarchy's transparency toggle hides the island and puts the widgets straight on the wallpaper, whereas `background-alpha` sets the island's translucency. Bar height is fixed rather than multiplied by the shell font scale.

## The island bar

The stock engine has no island, margin, or radius settings, so a floating bar needs a bar plugin (`kind: "bar"`). [mscurtescu/omarchy-island-bar](https://github.com/mscurtescu/omarchy-island-bar) ships three islands as a copy of the engine from Omarchy 4.0.2. That copy predates 4.0.3's `Commons.Color` qualification fix, the same namespace collision our Workspace Icons patch addresses, so we did not install it as-is.

Instead, `build-island-bar` copies the *installed* `Bar.qml` and `BarModel.js` from `/usr/share/omarchy/shell/plugins/bar/`, applies `patches/island-bar-overlay.patch` (about 80 changed lines), and writes `~/.config/omarchy/plugins/jdpinto.island-bar/` with its manifest and a `NOTICE` recording the MIT attributions. `omarchy bar use jdpinto.island-bar` selects it; `omarchy bar reset` returns to the stock bar. The generated directory is not in Git; the patch, the script, and the hook are. The overlay:

- Draws one island behind all three bar sections, inset from the side edges, and makes the bar surface itself clear.
- Puts the gap to the screen edge inside the bar's surface, so Hyprland reserves it: windows start below the island, and a hidden bar parks the gap off-screen too.
- Reads the island's geometry live from the `[island-bar]` section of `shell.toml`.
- Relaxes the engine's `required` properties and guards the widget registry, which a bar loaded from a plugin by URL needs. These loading changes come from mscurtescu's plugin.

Everything else, including popups, tooltips, drag-to-reorder, bar hiding, and the transparency toggle, is the stock engine. The existing `^omarchy-bar$` blur rule still applies: the layer namespace is unchanged, and the clear gap is below the rule's alpha threshold. We first ran the three-island layout; its overlay is kept in the `bar-unified-island-20261023T160810` backup.

### Settings

All in `home/.config/omarchy/shell.toml`, in logical pixels; saved changes apply live, without a shell restart:

```toml
[bar]
background-alpha = 0.93  # Kitty's background_opacity
size-horizontal = 28     # the island's height; tiles are 8 less

[island-bar]
edge-gap = 4   # island to the top of the screen
side-gap = 8   # island to the left and right screen edges
radius = 10    # corner radius: 8 matches window corners; 16 or more makes a pill
```

Omarchy ignores the `[island-bar]` section; only our bar reads it, falling back to these defaults for missing or invalid values. From the top of the screen down, the spacing is `edge-gap`, the island (`size-horizontal`), Hyprland's `gaps_out.top`, then the window. `gaps_out` and `gaps_in` live in `looknfeel.lua`.

### Window gaps and Omarchy's flush-bar service

Omarchy's first-party `omarchy.flush-bar` service manages the window gap on the bar's edge itself: 0 under a transparent bar, otherwise the largest of the four outer gaps, re-applied after every Hyprland config reload. It silently turned our `gaps_out.top = 3` into 8. We disabled it with `omarchy plugin disable omarchy.flush-bar`, so `looknfeel.lua` is authoritative for all four outer gaps. As a consequence, toggling the bar transparent no longer makes windows sit flush under it, and dragging the bar to another screen edge does not move that edge's gap with it. `omarchy plugin enable omarchy.flush-bar` restores the service.

### Matching the terminal

The island and Kitty share the theme `background` color (`#2d353b` in dark), the same 0.93 alpha, and the same Hyprland blur (`size = 4`, `passes = 2`), so the island and a focused terminal read as one material in both Everforest variants. The static test fails if `background-alpha` and Kitty's `background_opacity` drift apart. Two differences remain: `dim_inactive` darkens unfocused windows by 15%, which the bar layer does not get, and Kitty's `dynamic_background_opacity` can change one terminal's opacity at runtime, which the bar does not follow.

### Notification toasts

Omarchy places notification toasts from the bar's nominal height plus half of `gaps_out.top`, not from the bar surface's real size. With an `edge-gap` larger than that half, toasts overlap the island's bottom edge by the difference: with `edge-gap = 4` and `gaps_out.top = 3`, about 2 pixels, so they touch it. Panels opened from the bar, such as the calendar and audio panels, use the real surface size and clear the island. An `edge-gap` of at most half of `gaps_out.top` avoids the overlap; otherwise it is a limitation of Omarchy's notification service.

`~/.config/omarchy/hooks/post-update.d/30-island-bar` reruns `build-island-bar` after `omarchy update`, so the island bar follows engine updates automatically; the shell hot-reloads plugin code on save. If the overlay stops applying after an update, the hook fails loudly and `omarchy bar reset` restores the stock bar until the patch is rebased. `build-island-bar --check` reports whether the generated plugin matches a fresh build; the live test runs it.

Bar swaps and regeneration leave transient `Cannot read property ... of null` warnings from stock widgets whose `bar` is briefly unset; `omarchy restart shell` clears them, and the live test requires a clean log afterwards. Each shell start also logs one `Handler was registered but will not be used` warning for the `omarchy.bar` IPC target, because the stock bar is briefly instantiated as well. `omarchy-shell omarchy.bar` commands still reach the active island bar.

## Files and ownership

- `home/.config/omarchy/shell.toml` is the authored, selectively linked structural override, including the island's `[island-bar]` geometry. `link.sh` already discovers it; no root Stow operation is needed.
- `home/.config/hypr/looknfeel.lua` contains the targeted layer rule alongside the existing window appearance settings.
- `home/.config/omarchy/app-glyphs/` holds the vendored SVGs, unmodified, each source pinned beside its files: sketchybar-app-font (CC0) at the top level with `UPSTREAM_COMMIT`, Material Design Icons (`@mdi/svg`, Apache-2.0, license in `mdi/LICENSE`) in `mdi/`, and Simple Icons (CC0) in `simple-icons/`, both with `UPSTREAM_VERSION`. `link.sh` links each file.
- `home/.local/bin/bar-app-glyphs` maps window classes and terminal programs to those glyphs. `bar-app-glyphs json` prints the `iconOverrides` object; `bar-app-glyphs apply` stores it in the widget settings. Upstream maps macOS app names only, so this Linux mapping is ours.
- `home/.config/omarchy/bar/modules/jdp-menu.qml` is the menu-button module, with the same contract (`{ "id": "jdp-menu", "type": "qml" }`, first in `bar.layout.left`). The mark is two `Shape` paths in the drawing's own units (a 9-unit stroke on an 80-unit em), scaled to about 22 px tall at the default 12 px body font, with the lean as a skew about the foot line. The p's green is read from the theme's `colors.toml`, as the workspace rainbow does, since the shell's `Color` only carries foreground, accent and muted. Those two paths are the drawing's source: `tests/rasterize-mark.mjs` renders them to half-block text at 0.75 px per unit, and the static test checks that this is exactly `branding/about.txt` (regenerate it with `node tests/rasterize-mark.mjs <module> > about.txt` after a geometry change). Keystroke's widget is off the bar, so Keystroke is kept enabled by its own `{ "id": "evindor.keystroke" }` entry in `plugins`: a menu plugin with neither a bar entry nor a `plugins` entry is unloaded, and Super+Space stops working. `omarchy plugin list` still reports Keystroke as disabled, because for a bar widget that column means "on the bar".
- `home/.config/omarchy/bar/modules/front-app.qml` is the focused-app module, using the bar's documented custom-module contract (`bar`, `moduleName`, `settings` injected; `{ "id": "front-app", "type": "qml" }` in the layout). It accepts an optional `maxWidth` setting (default 180). Web apps resolve to the launcher whose Exec carries their URL, or, for handler-launched ones such as Zoom and HEY, whose `omarchy-webapp-handler-<slug>` matches a label of the host; otherwise the host is shown. Unlike plugin code, this directory is not hot-reloaded: after editing the module, run `omarchy restart shell`. The stock `omarchy.active-window` widget shows the full window title instead; we did not use it.
- `home/.local/bin/build-island-bar` generates the island bar plugin from the installed engine plus `patches/island-bar-overlay.patch`; `home/.config/omarchy/hooks/post-update.d/30-island-bar` reruns it after Omarchy updates.
- `~/.config/omarchy/shell.json` remains shell-owned and is not symlinked into the repository. It holds the current widget settings and layout, including later changes made in the UI, and `bar.id` selects the island bar.
- `~/.config/omarchy/plugins/woodenplastic.workspace-icons/` is the native installer's git checkout, not vendored into our overlay.
- `patches/workspace-icons-commons.patch` records the small compatibility change to that checkout, `patches/workspace-icons-rainbow-mono.patch` the rainbow and glyph support, and `patches/workspace-icons-kitty-probe.patch` the Kitty terminal-program fix, and `patches/workspace-icons-inactive-tiles.patch` the option to drop inactive tile fills, and `patches/workspace-icons-icon-per-window.patch` the option to show an icon per window. Apply them in that order.

The workspace entry in `shell.json` is, apart from `iconOverrides`:

```json
{
  "id": "woodenplastic.workspace-icons",
  "barStyle": "tiles",
  "activeTile": "accent",
  "coloredIcons": false,
  "tintStyle": "normal",
  "showNumbers": true,
  "iconPosition": "right",
  "maxIcons": 3,
  "showCounts": true,
  "showTerminalPrograms": true,
  "hideEmpty": true,
  "showSpecial": false,
  "showPreview": false,
  "rainbowWorkspaces": true,
  "inactiveTiles": false,
  "groupApps": false
}
```

`activeTile` only matters with the rainbow off; `rainbowWorkspaces` overrides it with the workspace's own color.

We tested version 1.2.3 at commit `0670a9fc7cfbd60bd2699d7bb885637bb71c6c57` on Omarchy `4.0.3rc4-1.1`. The plugin reads local desktop entries, icons, Hyprland state, and terminal process metadata. It runs a small local window-probe helper. No extra Python packages or network service are required for this setup; the optional tray helper is not enabled.

## Controls

- Click a workspace number to switch there, including an empty focused workspace.
- Click an app icon to focus its window; repeated clicks cycle its grouped windows.
- Right-click a workspace, or click the small grid button, to open settings.
- **Middle-clicking an app icon closes its window.** Middle-clicking a workspace sends the focused window there.
- Existing Super+number workspace bindings are unchanged.

Settings also open with `omarchy-shell woodenplastic.workspace-icons toggle`. For diagnostics, use `omarchy-shell woodenplastic.workspace-icons status`. The latter reports workspace keys, app counts, icon sources, and preview state as JSON.

## Installation and updates

On a fresh machine, use the native installer to clone the plugin disabled, review its source, and apply our patches before enabling:

```bash
omarchy plugin add https://github.com/woodenplastic/omarchy-workspace-icons.git --yes
plugin="$HOME/.config/omarchy/plugins/woodenplastic.workspace-icons"
patches="${DOTFILES_DIR:-$HOME/.dotfiles}/platforms/omarchy/patches"
for patch in workspace-icons-commons.patch workspace-icons-rainbow-mono.patch workspace-icons-kitty-probe.patch \
    workspace-icons-inactive-tiles.patch workspace-icons-icon-per-window.patch; do
    git -C "$plugin" apply --check "$patches/$patch"
    git -C "$plugin" apply "$patches/$patch"
done
omarchy plugin enable woodenplastic.workspace-icons
omarchy bar set woodenplastic.workspace-icons rainbowWorkspaces true --json
bar-app-glyphs apply
omarchy restart shell
```

Enabling replaces `omarchy.workspaces` in place. Set the other options above on that entry, retain `bar.transparent: false`, and move the clock with `omarchy bar move omarchy.clock --section right --after jankeesvw.notification-center`. If that anchor is not installed, move the clock to the end of the right section using the bar layout instead. Add the now-playing widget with `omarchy bar put omarchy.media --before omarchy.weather`. The app-name module has no `omarchy bar` command for custom entries; insert `{ "id": "front-app", "type": "qml" }` right after the workspace entry in `bar.layout.left` of `shell.json`, which hot-reloads. The bar finds the file at `~/.config/omarchy/bar/modules/front-app.qml` by its id. The menu button is the same kind of entry: replace `{ "id": "evindor.keystroke" }` at the start of `bar.layout.left` with `{ "id": "jdp-menu", "type": "qml" }`, add `{ "id": "evindor.keystroke" }` to `plugins`, and run `omarchy restart shell` (a module file that appeared after the shell started fails with "File name case mismatch" until then). Finally disable the flush-bar service so `looknfeel.lua` controls the window gap under the bar, then build and select the island bar:

```bash
omarchy plugin disable omarchy.flush-bar
hyprctl reload
build-island-bar
omarchy bar use jdpinto.island-bar
omarchy restart shell
```

The commons patch qualifies Omarchy's palette singleton as `Commons.Color` in two QML files. Unqualified `Color` resolved to Qt's color type on this build, leaving the active tile undefined and producing repeated runtime warnings. The patch changes namespace resolution only, including the preview's references in case we enable it later.

The rainbow/mono patch adds three things to the plugin:

- A `rainbowWorkspaces` option (off by default, listed in the manifest). The panel reads the named colors from the current theme's `colors.toml`, which the shell itself only partially exposes, and re-reads it when the shell's foreground, background, or accent change, which is how a theme switch arrives. Each workspace button then uses its own color wherever it used the panel's tint color, and the focused tile is filled with it.
- A `mono:` prefix for icon sources, resolved like any override path. The plugin's tint pipeline lifts an image's brightness and multiplies the tint color by the result, which lands a black glyph at about 60% of the tint. Mono images are lifted by exactly 1 instead, so black-on-transparent artwork comes out in the tint color, and glyphs stay colored in full-color mode too. The hover preview strips the prefix.
- Terminal-program detection now takes priority over an override for the terminal's own window class. Without this, mapping `kitty` to its glyph would have hidden the Neovim, Herdr, and other program icons in Kitty windows; now the Kitty glyph covers plain shells only.

The Kitty probe patch makes that detection work in Kitty at all. Both of the plugin's probes, the Python helper `scripts/window-probe` and the shell fallback in `Workspaces.qml`, read the foreground program from the terminal of the window process's *first* child. Kitty 0.49 starts a `kitten __atexit__` helper, which has no terminal, before the shell, so every Kitty window looked like a plain shell and showed the Kitty cat. The probes now use the first child that has a terminal. Upstream has the same code; the fix has not been reported there.

The inactive-tiles patch adds an `inactiveTiles` option, on by default so the plugin still looks like upstream. Upstream draws every workspace with windows on a tile of the bar's text color at 7% opacity, a translucent lightening over the island rather than a color of its own. With the option off, only the active tile is filled; a hovered workspace still gets its 12% highlight, so it stays clear what a click selects. The tiles keep their padding, so workspaces stay evenly spaced. Applying a patch with `git apply` replaces the files without triggering the plugin's hot reload; run `omarchy restart shell` afterwards.

The icon-per-window patch adds a `groupApps` option, on by default so the plugin still groups like upstream: one icon per app (or terminal program) with a window-count badge. Off, each window gets its own icon, so two plain Kitty windows show two Kitty icons and the count badge never appears. Icons keep the on-screen order of their windows, and clicking, middle-clicking, the tooltip, and the preview highlight then act on that one window. With several windows on the focused workspace, the focused window's icon gets the plugin's darker chip. `maxIcons` (3) still caps the icons per workspace and summarizes the rest as `+N`, always keeping the focused window's icon; the Mac shows every window, so raise it with `omarchy bar set woodenplastic.workspace-icons maxIcons 5 --json` if workspaces regularly hold more windows.

The mapping covers the apps installed here, including Omarchy web apps. Those open in the default browser, Brave Origin, with window classes such as `brave-youtube.com__-Default` (`<browser>-<host>__<path>-Default`, slashes as underscores). The static test requires that prefix on every web-app key: Apple Music was once keyed as `chrome-music.apple.com__-Default` and silently fell back to its tinted launcher icon. Classes for Apple Music, Slack, imv, and Disks were observed on real windows; other entries follow the same rule or the launcher's `StartupWMClass` but were not all observed. Terminal programs are keyed by process name (`aerc`, `btop`, `pi`), which also covers Omarchy's TUI launchers (`org.omarchy.<program>`).

To add an app, use the sketchybar-app-font glyph from the pinned commit when the font has the app itself, for parity with the Mac. The font's generic-looking glyphs are macOS app logos (Finder, Preview, Disk Utility, Final Cut Pro), so for Linux-only apps use a filled Material Design icon from the pinned `@mdi/svg` version instead, and Simple Icons for a brand neither has. Copy the SVG unmodified into the matching directory, add a line to the script's mapping (the glyph path without `.svg`, for example `mdi/folder`), and run `bar-app-glyphs apply`. GNOME's symbolic icons were also considered, but their thin outline style clashes with the filled glyphs. Strata, Kdenlive, Aether, and Omamail keep their own icons, which already tint to recognizable outlines.

The checkout intentionally has six local modifications. Review `git -C "$plugin" diff` before `omarchy plugin update woodenplastic.workspace-icons`; an upstream update touching those files may be refused rather than overwrite them. Do not use a hard reset to force an update. Review whether upstream has fixed the collision or the Kitty probe, or added equivalent options, adapt the recorded patches if needed, and rerun the checks. The live test rebuilds upstream `HEAD` plus all five patches in a temporary directory and compares it with the checkout, so a partial or drifted patch state fails loudly.

The shell may retain stale QML or duplicate popup handlers after a widget/layout reload. Once edits are complete, `omarchy restart shell` clears those caches without closing application windows. Do not use `omarchy refresh shell`, which resets the user's configuration.

## Verification and rollback

Source-only checks run without changing the desktop:

```bash
node platforms/omarchy/tests/test_bar_style.mjs
```

Add `--live` to check the installed widget settings, that the derived island bar is selected and matches a fresh build, that flush-bar is disabled and Hyprland's top window gap equals `looknfeel.lua`'s, that windows reserve the island plus its edge gap, that widgets sit past the edge gap, that the stored overrides equal the mapping script's output, that open apps resolve to existing glyph files, that the probe reports the foreground program of every Kitty window, that every icon stands for a single window, the focused workspace, the app-name module right of the workspaces with a visible width, now playing before the weather, no left/right overlap, widget heights equal to `size-horizontal`, rightmost clock, the exact patched checkout, and absence of these widgets' and the island bar's warnings in the current shell log:

```bash
node platforms/omarchy/tests/test_bar_style.mjs --live
hyprctl configerrors
```

We also checked the workspace settings popup and stock clock/audio popup routing, switched Everforest light and back to dark, and inspected bar captures in both variants, with the island and with the clock's calendar panel open under it. Changing `radius` and `edge-gap` in the linked `shell.toml` updated the island and the windows' reserved space live, without a restart. A labeled test notification confirmed the toast overlap described above. Pixel samples confirmed the glyphs and numbers share one exact palette color per workspace (for example `#e69875` in dark, `#dfa000` in light), the focused tile uses the theme background as ink, and the glyph edges blend cleanly with no halo. Existing application windows and their workspace assignments were preserved. Before choosing icon sources, we rendered every launcher on this machine through the plugin's own tint formula (Qt MultiEffect's shader: Rec. 601 luma of the color plus 0.6, times the tint, clamped only on output; it matched a live pixel exactly) beside the candidates from each source. After the change, live captures showed Apple Music's note, Slack's glyph, imv's picture, and aerc's envelope and Herdr's glyph in Kitty windows. Multi-monitor behavior, vertical bar positions with islands, the dots style with the rainbow, and every terminal/multiplexer combination have not been exercised.

The original `shell.json`, `looknfeel.lua`, pristine plugin files, and before/after bar captures are outside Git under `~/.local/state/omarchy/backups/bar-workspace-icons-20261018T092638/` (first pass), `~/.local/state/omarchy/backups/bar-glyphs-rainbow-20261018T145716/` (glyphs and rainbow, with dark and light captures), `~/.local/state/omarchy/backups/bar-front-app-media-20261019T163208/` (app name and now playing), `~/.local/state/omarchy/backups/bar-islands-20261019T164024/` (three islands, dark and light, clock popup), and `~/.local/state/omarchy/backups/bar-unified-island-20261023T160810/` (single island: previous overlay, `shell.toml`, flush-bar state, gaps, and captures), and `~/.local/state/omarchy/backups/bar-icon-sources-20261027T082000/` (icon sources: previous mapping script, pristine probe files, the comparison sheets, and before/after captures). The `-latest` pointer files next to them name those directories. `shell.toml.was-absent` records that there was no machine-level shell override before this change.

For a selective rollback:

1. To return to the flat stock bar, run `omarchy bar reset` and `omarchy plugin enable omarchy.flush-bar`; remove `~/.config/omarchy/plugins/jdpinto.island-bar/` and the post-update hook link if the plugin should go too. To return to three islands instead, restore the previous overlay from the unified-island backup and run `build-island-bar`.
2. To drop the app name or now playing, remove the `front-app` entry from `bar.layout.left` in `shell.json`, or run `omarchy plugin disable omarchy.media`. To bring back the Omarchy logo, replace the `jdp-menu` entry with `{ "id": "evindor.keystroke" }`; the extra `plugins` entry is then redundant but harmless. The `shell.json` from before this change is in `~/.local/state/dotfiles-migration/backups/shell-json-20261025-174905/`.
3. To keep the widget but drop only the new look, run `omarchy bar set woodenplastic.workspace-icons rainbowWorkspaces false --json`, `omarchy bar set woodenplastic.workspace-icons iconOverrides '{}' --json`, `omarchy bar set woodenplastic.workspace-icons inactiveTiles true --json`, and `omarchy bar set woodenplastic.workspace-icons groupApps true --json`; the patched plugin then behaves as upstream. Set `size-horizontal = 32` in `shell.toml` for the previous bar height. Reverse the patches in the opposite order with `git -C "$plugin" apply --reverse` (icon per window, inactive tiles, Kitty probe, then rainbow/mono) if the code should go too. The mapping script from before the Material Design and Simple Icons additions is in the icon-sources backup.
4. Run `omarchy plugin disable woodenplastic.workspace-icons`; Omarchy restores its stock workspace widget in place.
5. Move the clock back with `omarchy bar move omarchy.clock --before omarchy.keyboard-layout`.
6. Remove the new `[bar]` overrides from the authored `shell.toml` and the targeted `hl.layer_rule` block from `looknfeel.lua`, preserving any unrelated later edits.
7. Run `hyprctl reload`, `hyprctl configerrors`, and, if needed, `omarchy restart shell`.

The retained backups are for comparison or an immediate full rollback, not a reason to overwrite newer settings. Nothing under `/usr/share/omarchy/`, the macOS SketchyBar configuration, or credentials was changed.
