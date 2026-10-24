# Kanata keyboard setup

The full keyboard configuration is installed permanently. `kanata.service`
starts at boot; `kanata-palm-guard.service` starts in the Hyprland user session.
The accepted Caps-only and five-minute trial profiles remain as fallback tools.
The full SpaceFN layer includes navigation/media keys from the active Mac
profile, with previous/next-track transport adapted for Linux. Right Alt,
desktop bindings, the native two-Shift Caps behavior, and saved trackpad settings
are unchanged. Only the built-in trackpad pauses during the navigation layer.

## Permanent setup

- `/etc/kanata/kanata.kbd` and `/etc/kanata/keymap.kbd`: reviewed, root-owned
  copies, not links into a writable home directory.
- `/etc/systemd/system/kanata.service`: root remapper with filesystem/capability
  hardening, no TCP server, and `Restart=on-failure` rather than restart-always.
- `/etc/modules-load.d/kanata.conf`: ensures uinput is available at boot.
- `~/.config/systemd/user/kanata-palm-guard.service`: unprivileged desktop guard.
- `kanata_guard_session.py`: filters the remapper's journal by invocation,
  restores the touchpad on remapper stop/restart, recovers the current layer on
  observer restart, and reasserts the pause after compositor config reloads.
- `$XDG_RUNTIME_DIR/kanata/guard-state.json`: ephemeral observer health/layer
  state; no raw key events or window titles are logged by the observer.

The persistent observer uses a lifetime pidfd watchdog, **not** the trial's
330-second cap. It also has systemd exit recovery. The keyboard keeps working
when the installation terminal is closed; no five-minute timeout remains.
No input/uinput group membership or broad device-permission rules were added.

**Emergency stop:** hold physical **Left Control + Space + Escape**. Kanata
exits successfully and systemd does not immediately restart it. Start it again
explicitly in a terminal:

```bash
sudo systemctl start kanata.service
```

Status and logs:

```bash
systemctl status kanata.service --no-pager
systemctl --user status kanata-palm-guard.service --no-pager
journalctl -u kanata.service -n 40 --no-pager
journalctl --user -u kanata-palm-guard.service -n 40 --no-pager
```

To stop both components temporarily:

```bash
sudo systemctl stop kanata.service
systemctl --user stop kanata-palm-guard.service
```

To remove automatic startup, use `disable --now` instead of `stop` for both.
After stopping, Caps is ordinary Caps Lock (Compose remains disabled), and Space
is ordinary Space. The original Escape/Control keys remain available.

### Editing and redeploying

Edit `keymap-spacefn.kbd` as the canonical full keymap. The root-owned deployed
copy deliberately does not change until reviewed redeployment. Run:

```bash
~/.local/bin/kanata-install-system
```

This validates a staged copy, requests sudo in the terminal, copies configuration
and the service unit into `/etc`, and verifies both services and the virtual
keyboard. Previous system files are backed up under `/etc/kanata/backups/`.
The authored service/wrapper live under `system/`. The installer log and latest
system backup path are under `~/.local/state/kanata/`.

Service startup, root file ownership, deployed/source equality, journal access,
and virtual-keyboard creation were verified. There were no startup errors or
service restarts. Guard logic passes 21 lifecycle/recovery tests in addition to
260 keymap simulations. Reboot, suspend/resume, lock/unlock, and the physical
emergency exit under systemd still need a controlled manual check; none was
forced during installation. Early-boot disk-unlock prompts are outside this
normal-system remapper. The two-Shift Caps behavior remains Hyprland/XKB's, not
a new Kanata mapping for Linux consoles.

## Files

- `kanata.kbd`: Linux device selection. Only `Apple SPI Keyboard` is grabbed.
  The output keyboard is named `kanata-caps-trial`.
- `keymap.kbd`: reusable mapping: a short Caps tap emits Escape; another
  key pressed while Caps is down resolves it immediately to Left Control;
  holding Caps alone resolves to Control after 200 ms.
- `~/.local/bin/kanata-caps-trial`: original five-minute Caps-only trial.
- `spacefn.kbd` / `keymap-spacefn.kbd`: separate Linux wrapper and Caps +
  SpaceFN mapping. The output keyboard is named `kanata-spacefn-trial`.
- `~/.local/bin/kanata-spacefn-trial`: five-minute Caps + SpaceFN trial.
- `spacefn_touchpad_guard.py`: unprivileged Linux layer-log observer and
  independent recovery watchdog; pauses only `apple-spi-trackpad` during Nav.
- `tests/spacefn_simulation.py`: offline regression tests using Kanata 1.12.0's
  simulator, not real keyboard injection.
- `tests/test_touchpad_guard.py`: parser, restoration, and watchdog unit tests.
- `tests/check_media_bindings.py`: read-only media-keycode -> current XKB ->
  existing Omarchy binding verification; never executes a media/brightness action.
- `~/.local/state/kanata-trial/`: original install/test logs and the pre-change
  Hyprland backup. Trial 2 logs and its simulation summary are in `spacefn/`.
  Live logs use normal informational output, not debug key-event tracing.

The zero tap-repress timeout is deliberate: tapping Caps, then immediately
using Caps as Control, should not hold/repeat Escape instead.

## Start and stop

Run this in a visible terminal:

```bash
~/.local/bin/kanata-caps-trial
```

It checks the configuration and refuses to run alongside another Kanata/keyd
process. Press Enter when ready and enter your sudo password if prompted.
Release all keys during Kanata's startup delay. The trial runs for at most
five minutes, with a five-second forced-stop grace period if necessary.

To stop early, hold the **physical Left Control + Space + Escape** keys
simultaneously. Caps-as-Control does not substitute for physical Left Control
in this emergency sequence. Ctrl+C in the trial terminal also stops it;
therefore test Caps+C in a different application, not that terminal.

After stopping, the keyboard is no longer intercepted. Caps becomes ordinary
Caps Lock because Hyprland's Caps-as-Compose option was removed. Escape/Control
remain available on their original physical keys. Close the finished trial
window before opening another trial.

No input/uinput group memberships, device permissions, udev rules, autostart
entries, or service-enablement settings are changed by this helper. The AUR
package supplies a minimal service; the permanent setup overrides it with the
reviewed unit described above. Trial helpers refuse to run alongside the active
permanent remapper.

## Full Caps + SpaceFN trial

Run this in a visible terminal:

```bash
~/.local/bin/kanata-spacefn-trial
```

Like the original helper, it waits for Enter, checks for another remapper,
uses the physical Left Control + Space + Escape emergency exit, and stops
automatically after five minutes. Both helpers share a lock; close a finished
trial window before opening another.

### Initial Space policy: 180 ms hold

- Tap and release Space within 180 ms to type Space. This includes Neovim
  leader sequences: release Space before the next key.
- Hold Space for about 180 ms, then use H/J/K/L for Left/Down/Up/Right. Once the
  layer is active, subsequent navigation keys do not wait for another timeout.
- Add Shift for selection, or Caps/Control for Control+arrow word movement.
  Both modifier orders (before and after activating SpaceFN) are supported.
- Use a **quick Ctrl+Space tap** (under 180 ms) for the tmux prefix. A longer
  Ctrl+Space hold is reserved for Control+arrow navigation instead.
- A **quick Super/Command+Space tap** (under 180 ms) opens the menu on release.
  Holding Space instead enables Super+arrows, whether Super or Space was pressed
  first. There is no longer a Super-specific bypass. A long lone Super+Space
  hold enters navigation and does not open the menu.
- A long lone Space hold does not type repeated spaces. Space+B emits a literal
  space while the layer remains active. Navigation, editing, brightness, and
  media keys are listed below; no Right Alt launcher layer has been added.

This is deliberately a conservative timed hold, not an immediate chord like
Karabiner's SpaceFN rules. It uses `tap-hold`, not `tap-hold-press`, so a fast
roll from Space into H/J/K/L should remain literal text. Typing with Space
still held past 180 ms can intentionally activate navigation. Report accidental
arrows, missing spaces, or uncomfortable initial navigation delay before we
tune the policy or enable permanent startup.

### Full layer reference

Hold Space for about 180 ms, then use:

| Key | Output |
| --- | --- |
| H / J / K / L | Left / Down / Up / Right |
| M / comma | Page Down / Page Up |
| N / period | Home / End |
| Backspace | Forward Delete |
| Slash | Backtick; add Shift for tilde |
| B | Literal Space; remain in the layer |
| 1 / 2 | Display brightness down / up |
| 7 / 8 / 9 | Previous track / Play-Pause / Next track |
| 0 | Mute |
| Minus / equals | Volume down / up |

Home/End and Page Up/Down are real keycodes, not application-specific macros;
their exact behavior remains Linux/application-native. Delete is a real Delete
key and can be destructive in a file manager: test it in disposable text first.

Space+7/9 intentionally emit previous/next-track events rather than the Mac
profile's rewind/fast-forward events. Omarchy already handles previous/next;
continuous seeking would require a separate player-aware decision. The current
Brave MPRIS player reported `CanGoPrevious=false` and `CanGoNext=false` during
inspection, so use a playlist-capable player when testing these keys. Play/Pause,
volume, and brightness use their normal existing Omarchy handlers.

Modifiers pass through for every key. This preserves Shift selection, Ctrl+
Home/End, and Shift+Slash -> tilde, but also preserves Omarchy's modified media
shortcuts: Alt for precise adjustments, Shift+brightness for keyboard backlight,
and its Super+volume screenshot bindings. Test media without modifiers first.
No Hyprland bindings, physical Escape, Fn/Touch Bar mappings, or Right Alt
launcher behavior were changed. The 200 ms Caps policy, 180 ms Space policy,
Super key-order fix, and accepted palm guard remain unchanged.

### Trackpad safeguard

libinput's disable-while-typing intentionally ignores arrow keys and modifier
combinations. Kanata emits these rather than the raw H/J/K/L presses during
navigation, so the ordinary typing timeout does not cover this hold. A palm
movement/click can then move the caret or change focus under Omarchy's existing
focus-follows-pointer behavior. This is not evidence that Kanata lost its layer.

The Linux guard pauses **only the built-in trackpad** when Kanata reports
entry into `nav`. It restores the trackpad when Space releases the layer, on
remapper/observer exit, and on ordinary interruption. Deliberate trackpad use is also
unavailable during Nav; external mice are unaffected. The pause begins after
the 180 ms hold decision, not at Space key-down. Normal tapping, scrolling, and
three-finger dragging outside navigation retain their existing settings.

The observer runs as the desktop user and uses the installed Hyprland Lua
`hl.device()` API. It does not use persistent Omarchy toggle files, edit input
config, access raw input, enable a TCP server, or run commands inside root-owned
Kanata. It parses the version-pinned layer log rather than raw keystrokes.

Recovery has three paths: the observer's `finally`, a detached Linux pidfd
watchdog (including SIGKILL), and the trial shell's exit cleanup. Per-trial tokens
and an inherited IPC lock prevent stale watchdogs/late requests from racing a
new trial. The watchdog has a 330-second fail-open limit; normal exit stops it
immediately. The existing 300-second Kanata timeout remains in force. An explicit
Omarchy touchpad disable made by the user during the trial is respected.

Trial helpers require the touchpad to be enabled initially. The permanent guard
respects a persisted Omarchy touchpad disable and reasserts its runtime pause on
compositor reloads. This is a navigation safeguard, not calibrated hardware
palm rejection. If the
compositor cannot accept recovery IPC, the helper prints the keyboard-accessible
recovery command:

```bash
omarchy toggle touchpad on
```

No changes to libinput quirks, palm-size thresholds, global focus-following,
input groups, or saved trackpad settings have been made.

### SpaceFN acceptance tests

1. Type normal prose quickly, especially `hello`, `just`, `keep`, and `like`
   after spaces. Spaces and letters should not disappear or become arrows.
2. Try both roll orders: release Space before the letter, and release the
   letter first while briefly overlapping Space.
3. Hold Space, then navigate with each of H/J/K/L. Hold a direction for repeat.
4. Add Shift for selection and Caps/Control for word movement in a text field.
   Exact Ctrl+arrow behavior remains application-specific.
5. Release Space before releasing an arrow key; then type H/J/K/L normally.
6. Check a quick Ctrl+Space tap in tmux and a quick Super+Space tap for the menu.
   Then test Super+Space+H/J/K/L in both key orders; held navigation must not open
   the menu or invoke the separate Super+H/J/K/L bindings.
7. Check tap-and-release Space leader sequences in Neovim. Do not chord the
   leader with the next key when testing ordinary leader sequences.
8. Recheck the accepted Caps behavior. Once Nav is active, lightly brush the
   trackpad: pointer/focus/caret should stay put. Release Space and confirm the
   trackpad works again. Check normal typing/palm behavior outside Nav separately.
9. In disposable text, test Page Up/Down, Home/End, forward Delete, backtick,
   Shift+Slash for tilde, and Space+B followed by more navigation. Use Caps/Control
   with Home/End and Shift with navigation to verify normal modifier behavior.
10. Test brightness up (Space+2) before brightness down. Test volume/mute and
    play/pause without modifiers, then previous/next with a capable player.
11. Stop with the physical emergency sequence and confirm the keyboard and
    trackpad return to normal. Caps is ordinary Caps Lock and Space is ordinary
    Space afterward.

### Offline verification

The full candidate passed 260 simulation checks against the version-matched
upstream simulator: accepted Caps behavior, all SpaceFN outputs, ordinary-key
passthrough, repeat routing, layer release, modifiers, Ctrl+Space taps, Super+
Space tap/hold behavior and both key orders, Right Alt passthrough, and fast typing
rolls/nested taps for every newly mapped key. Every completed sequence is checked
for balanced releases. Simulated media events never execute real media actions.

The unchanged guard passes 13 unit tests, including the expanded multirow layer
format. Earlier short live IPC probes passed normal restoration and abrupt
SIGKILL recovery, and the parser recognizes the full layer's actual simulator
logs. The user also confirmed the refined H/J/K/L and palm-guard behavior worked
perfectly before this extension.

A read-only libxkbcommon check verified all eight media/brightness keycodes against
the current keyboard layout and actual Omarchy bindings. No audio, brightness,
playback, or desktop bindings were changed by these checks. The new physical
keys and player/application behavior still need the acceptance tests above.

To rerun with an upstream simulator built from Kanata v1.12.0:

```bash
python ~/.config/kanata/tests/spacefn_simulation.py \
  --simulator /path/to/kanata_simulated_input
```

The simulation source archive was SHA-256-verified against the reviewed AUR
package; the simulator was built offline in a temporary directory with existing
Cargo dependencies. It opens no real input device. The source/build location is
recorded in `~/.local/state/kanata-trial/spacefn-audit-path`; temporary build files
can be recreated if removed. The saved `spacefn/simulation-summary.txt` records
the result for this candidate. `spacefn/guard-recovery-summary.txt` records the
live recovery checks. `spacefn/media-routing-summary.txt` records the read-only
media checks. To rerun those checks:

```bash
python -B ~/.config/kanata/tests/check_media_bindings.py
```

To run the guard unit tests without toggling real devices:

```bash
python -B -m unittest discover -s ~/.config/kanata/tests \
  -p 'test_touchpad_guard.py' -v
```

The pre-refinement files are saved under `~/.local/state/kanata-trial/backups/`;
`spacefn/refinement-backup-path` records the exact folder. The Caps-only config
and helper were not modified. The accepted pre-extension SpaceFN files are also
backed up; `spacefn/extension-backup-path` records that folder.

The full layer was accepted and promoted to normal startup. The remaining
manual checks are reboot, suspend/resume, lock/unlock, and recovery under systemd.

## Caps-only manual acceptance tests

1. In a disposable editor buffer, quickly tap Caps to leave insert mode.
2. In a GUI text field, use Caps+A to select all, then copy/paste with Caps+C/V.
3. In a separate terminal, test Caps+L and Caps+U against disposable input.
4. Hold Caps alone beyond 200 ms, then try a Control shortcut. A long lone
   hold is Control, not Escape when released.
5. Tap Caps, then immediately press Caps+A; it should still be Control+A.
6. Check Shift+Caps chords, normal Shift typing, repeated taps, and fast typing.
7. Test Omarchy's existing two-Shift Caps behavior: both Shifts enable Caps
   Lock, and a subsequent lone Shift clears it (`shift:both_capslock_cancel`).
8. Confirm Super+Space, Ctrl+Space in tmux, Space/Neovim leader sequences,
   and Right Alt have not changed.
9. Test tap-to-click and palm rejection while typing. Kanata creates a virtual
   keyboard; disable-while-typing needs physical verification on this hardware.
10. Stop with the emergency sequence and confirm the original keyboard works.

Also check suspend/resume, lock/unlock, recovery, and an external keyboard.
The permanent remapper deliberately does not use restart-always: successful
emergency exits must not be undone by automatic restart.

## Hyprland change and rollback

The only intended change to `~/.config/hypr/input.lua` is an explicit:

```lua
kb_options = "shift:both_capslock_cancel",
```

This retains Omarchy's current two-Shift Caps behavior and removes
`compose:caps`. To restore Omarchy's keyboard options, remove this override
and run `hyprctl reload`, then `hyprctl configerrors`. This leaves subsequent
trackpad edits intact. A full pre-change backup is also stored under
`~/.local/state/kanata-trial/backups/`; its path is recorded in
`hypr-input.backup-path`.

## macOS later

`keymap-spacefn.kbd` can be included by a macOS-specific device wrapper for the
full setup (`keymap.kbd` is the preserved Caps-only fallback). Device names
must be discovered on the actual Mac; this Linux wrapper is not a Mac setup.
Kanata can replace Karabiner-Elements' remapping rules and app, but macOS still
requires the standalone Karabiner DriverKit VirtualHIDDevice driver and daemon,
privacy permissions, and privileged Kanata startup. Kanata 1.12.0's documented
driver version is 6.2.0. Do not run both remappers against the same device.

- https://github.com/jtroo/kanata/blob/v1.12.0/docs/setup-macos.md
- https://github.com/jtroo/kanata/blob/v1.12.0/docs/config.adoc
- https://aur.archlinux.org/packages/kanata
