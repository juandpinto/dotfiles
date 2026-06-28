# SketchyBar Config Notes

## Layout

Two floating islands on a transparent bar (`color=0x00000000`):

```
 [workspaces + front app]          [♫ now playing | wifi | cpu | vol | bat | clock] 
```

- **Left island** (`left_island` bracket): `space.1`–`space.9` + `space_separator` + `front_app`
- **Right island** (`right_island` bracket): `media` + `wifi` + `cpu` + `volume` + `battery` + `clock`
- **Apple logo** (`apple`): standalone item, outside the left island, far left

Right-side items are added in reverse visual order (SketchyBar stacks `right` items right-to-left),
so `clock` is added first (rightmost) and `media` last (leftmost).

---

## Theme: VS Code Dark+

Derived from [`mofiqul/vscode.nvim`](https://github.com/mofiqul/vscode.nvim) — the same theme used in nvim and wezterm.
Auto dark/light switching is not implemented in SketchyBar; config targets dark mode.

| Variable        | Hex       | ARGB              | VS Code name      | Use                          |
|-----------------|-----------|-------------------|-------------------|------------------------------|
| `TEXT`          | `#d4d4d4` | `0xffd4d4d4`      | `vscFront`        | Default icon/label color     |
| `SUBTEXT1`      | `#808080` | `0xff808080`      | `vscGray`         | Dimmed labels (front app)    |
| `MAUVE`         | `#c586c0` | `0xffc586c0`      | `vscPink`         | Media icon accent            |
| `BLUE`          | `#569cd6` | `0xff569cd6`      | `vscBlue`         | Clock, CPU, WiFi icons       |
| `GREEN`         | `#b5cea8` | `0xffb5cea8`      | `vscLightGreen`   | Battery charging             |
| `RED`           | `#f44747` | `0xfff44747`      | `vscRed`          | Battery critical, WiFi down  |
| `YELLOW`        | `#ce9178` | `0xffce9178`      | `vscOrange`       | Battery low warning          |
| `ISLAND_BG`     | `#1f1f1f` | `0x881f1f1f`      | `vscBack`         | Island background (frosted)  |
| `ISLAND_BORDER` | `#569cd6` | `0x40569cd6`      | `vscBlue`         | Island border (subtle blue)  |
| Active WS pill  | `#007acc` | `0xff007acc`      | VS Code brand blue| Focused workspace background |

### Auto dark/light switching

`dark_mode_watcher.sh` runs as a persistent background process (launched via `nohup`/`disown`
from `sketchybarrc`). It polls `defaults read -g AppleInterfaceStyle` every 2 seconds and
calls `sketchybar --reload` when the appearance changes. The watcher survives reloads; a
`pgrep` guard in `sketchybarrc` prevents duplicate instances.

Plugins that use hardcoded colors (`battery.sh`, `wifi.sh`, `aerospace.sh`) each call
`defaults read -g AppleInterfaceStyle` to pick the correct color at runtime.

### Switching back to Catppuccin Mocha

The Catppuccin palette is commented out directly below the VS Code block in `sketchybarrc`.
Swap the commented/active lines and reload:

```bash
sketchybar --reload
```

---

## Nerd Font Codepoints Used

All glyphs use `Hack Nerd Font` unless noted.

| Item          | Glyph | Codepoint  | Nerd Font name              |
|---------------|-------|------------|-----------------------------|
| Apple logo    |       | `U+F179`   | `nf-fa-apple`               |
| Clock         |       | `U+F017`   | `nf-fa-clock_o`             |
| CPU           |       | `U+F2DB`   | `nf-fa-microchip`           |
| Battery full  |       | `U+F240`   | `nf-fa-battery_full`        |
| Battery 75%   |       | `U+F241`   | `nf-fa-battery_three_quarters` |
| Battery 50%   |       | `U+F242`   | `nf-fa-battery_half`        |
| Battery 25%   |       | `U+F243`   | `nf-fa-battery_quarter`     |
| Battery empty |       | `U+F244`   | `nf-fa-battery_empty`       |
| Charging bolt |       | `U+F0E7`   | `nf-fa-bolt`                |

Volume icons (`nf-md-*`) are set dynamically in `plugins/volume.sh` via `volume_change` event.

---

## App Icons Font: `sketchybar-app-font`

Workspace labels use `sketchybar-app-font` to render app icons as ligatures (e.g. `:safari:`).

- **Install:** `brew install font-sketchybar-app-font`
- **Repo:** https://github.com/kvndrsslr/sketchybar-app-font
- **Update icon map:**
  ```bash
  curl -L "https://github.com/kvndrsslr/sketchybar-app-font/releases/latest/download/icon_map.sh" \
    -o ~/.config/sketchybar/plugins/icon_map_fn.sh
  ```

---

## ⚠️ Writing Unicode Glyphs to Files

**Do not embed Nerd Font / Unicode glyphs directly in bash heredocs** — they get stripped.

Instead, use Python to write them by codepoint:

```python
python3 << 'PYEOF'
with open('/path/to/plugin.sh') as f:
    content = f.read()

content = content.replace('PLACEHOLDER', '\uf179')  # use \uXXXX codepoint

with open('/path/to/plugin.sh', 'w') as f:
    f.write(content)
PYEOF
```

Or to add a glyph variable at the top of a script:
```python
content = content.replace('ICON=""', f'ICON="\uf240"')
```

---

## Reloading

```bash
sketchybar --reload
```

Query any item for debugging:
```bash
sketchybar --query <item_name>   # e.g. sketchybar --query left_island
```

---

## Plugins

| File                 | Trigger                  | Notes                                 |
|----------------------|--------------------------|---------------------------------------|
| `aerospace.sh`       | `aerospace_workspace_change` | Colors active WS pill mauve       |
| `space_windows.sh`   | workspace/app events     | Updates app icon strip in WS labels   |
| `front_app.sh`       | `front_app_switched`     | Shows focused app name                |
| `clock.sh`           | every 30s                | Format: `Sat 27 Jun  01:45 PM`        |
| `battery.sh`         | every 2min + events      | Color-coded by level                  |
| `volume.sh`          | `volume_change`          | Icon reflects level                   |
| `wifi.sh`            | every 30s                | Icon reflects signal strength (RSSI)  |
| `cpu.sh`             | every 5s                 | `top -l 1` user+sys %                 |
| `media.sh`           | every 5s                 | Music.app only; hides when not playing|
| `dark_mode_watcher.sh` | continuous (2s poll)   | Reloads bar on macOS appearance change|
| `icon_map_fn.sh`     | called by space scripts  | App name → ligature string            |
