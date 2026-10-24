# Pi on Linux

We have migrated the authored Pi resources while preserving Linux's existing agent directory and runtime state. Run `/reload` in an existing Pi session to discover the new skills, instructions and extensions; a new Pi process picks up all startup preferences. We have not reloaded the active coding session automatically.

## Source and runtime boundary

- Shared authored resources: `~/.dotfiles/.config/pi/agent/`.
- Linux settings: `~/.dotfiles/platforms/omarchy/home/.pi/agent/settings.json`.
- Active Linux agent directory: `~/.pi/agent/`, a real directory, not a link into Git.
- The Mac's XDG layout and settings remain unchanged. We do not change `PI_CODING_AGENT_DIR` on Linux.
- Only the authored instructions, keybindings, model definitions, individual skill/extension entries and theme files are linked. The Linux linker preserves the existing `omarchy` and `diagnose-crash` skills.
- `auth.json`, `sessions/`, `models-store.json`, `npm/` and git package caches remain local. We have not copied, replaced or printed credentials or session history.

## Installed resources

The nine personal skills are `documentation`, `python`, `grill-me`, `mh-wiki`, `personal-wiki`, `officecli`, `officecli-docx`, `officecli-pptx`, and `officecli-xlsx`. Together with the two Omarchy skills, real Pi resource discovery finds eleven skills without duplicate-resource errors.

We also linked the global agent instructions, custom PageUp/PageDown half-page bindings, both Everforest themes, the archived custom Catppuccin theme, the empty shared `models.json`, the destructive-command guard, the commit-secret guard, Lookback, and notifications. `pi-rewind@0.5.0` is installed in Pi's real local npm directory; its `/rewind` command registers successfully. We have not performed a destructive restore on a real project to test it.

## Linux and Pi 1.2 adjustments

### Omarchy-driven appearance

Linux selects `"theme": "everforest-omarchy"`. The existing `20-shared-appearance` theme-set hook reads Omarchy's current dark/light mode, copies the corresponding linked `everforest-dark.json` or `everforest-light.json` into `~/.pi/agent/themes/everforest-omarchy.json`, and changes only its `name` and explicit `appearance` metadata. All palette variables, semantic colors, and export colors remain exactly as authored. The generated file stays outside Git; `PI_CODING_AGENT_DIR` is honored when explicitly set.

Pi's native custom-theme watcher hot-reloads that fixed file. We no longer use the terminal-detected `everforest-light/everforest-dark` pair on Linux: Herdr can announce a new appearance before its background-color query returns the new color, leaving Pi on the outgoing palette until `/reload`. See [Herdr's propagation/ordering issue](https://github.com/herdrdev/herdr/issues/4183) and the [matching Pi report](https://github.com/earendil-works/pi/issues/10494). The Mac retains its existing theme-following package and settings.

Publication uses a private temporary file and atomic rename, preserving the last valid theme if conversion fails. The hook then touches the final filename: the bundled Pi build can coalesce rename events under the temporary filename, which its filename-filtered watcher ignores. Touching the completed file makes the existing watcher reliable without exposing partial JSON. There is no new daemon, polling loop, or installed Pi extension.

After initially linking the overlay, run `everforest dark` (or run `bash ~/.config/omarchy/hooks/theme-set.d/20-shared-appearance` to seed Pi without changing the desktop theme). Then run `/reload` once in an existing Pi session to select the new fixed theme. Subsequent switches update the running UI without reloading Pi. This does not replace the active coding session automatically.

Omarchy's ordinary theme-set helper separately updates its generated `omarchy-system` theme; it does not overwrite our custom selection unless explicitly called with `--activate`.

For rollback, restore `"theme": "everforest-light/everforest-dark"` in the Linux settings, remove only the Pi-publication block from `20-shared-appearance`, and run `/reload`. Keep the shared appearance-cache and tmux updates. The generated file can remain harmlessly unused. Pre-change settings and the hook are backed up outside Git under `~/.local/state/omarchy/backups/`; `pi-appearance-latest` names the backup directory.

### Notifications

The shared extension now sends Kitty OSC 99 when Kitty is detected and preserves OSC 777 for WezTerm/Ghostty-compatible terminals. Both use stderr and tmux DCS passthrough. Titles and bodies are stripped of control characters, preventing message text from becoming terminal control sequences. Tests build and inspect escape sequences without sending desktop notifications. The original three-second settled-run debounce is retained.

### Lookback

The custom overlay is restricted to `ctx.mode === "tui"`. Pi RPC reports `hasUI` for dialogs, but does not support terminal overlays; checking only `hasUI` could otherwise clear an RPC editor after a no-op overlay. The read-only TUI behavior and Alt+R mapping remain.

### Guards and settings

Both guard rule suites pass on Linux. macOS `/Users/...` paths are test fixtures, not runtime assumptions. Runtime paths use HOME/TMPDIR and include Linux temp roots. The guards remain best-effort safety checks, not a sandbox.

Linux has the same useful UI defaults as the Mac, while retaining Pi 1.2's changelog version. The Mac's default `github-copilot/gpt-5.6-luna` exists in this installation's available model registry and supports the configured `xhigh` thinking level. The startup audit confirmed both without sending a model request. Model availability does not substitute for an API request/authentication test; current local credentials were retained.

## Dependencies and data not migrated

- The wiki instructions use ordinary home-relative paths and are portable, but the repositories are not present at `~/Documents/personal-wiki/` or `~/Documents/MH/mh-wiki/` here. The skills are available; we need the relevant checkout before using them. We have not guessed a work repository URL or copied private Mac documents.
- MH wiki's optional Confluence workflow assumes an Atlassian MCP connection. No MCP server configuration was included in these tracked Pi files, so that integration is not configured by this migration.
- OfficeCLI's instructions support Linux, and the current upstream release includes `officecli-linux-arm64`. The executable is not installed. We have not run its network installer automatically. Viewer/font fidelity remains something to check on real documents.
- The Python skill's uv-based workflow is portable. uv is installed; Ruff/ty are not currently global shell commands (ty is installed for Neovim through Mason). We can use uv-managed tools or install them explicitly when needed.
- MH wiki's Prettier/Markdownlint commands require the project's formatter dependencies; neither is globally installed. A missing project tool is a dependency gap, not a reason to alter the wiki's formatting policy.

## Verification

- `node platforms/omarchy/tests/audit_pi.mjs` starts real Pi RPC in a temporary non-project directory with `--offline --no-session` and never sends a prompt. All eleven skills, `/lookback`, and `/rewind` are present, the model/thinking defaults match, and startup stderr is empty.
- The original terminal-mode startup/exit probe loaded the custom theme pair and extensions. The replacement appearance check, `node platforms/omarchy/tests/test_pi_appearance.mjs --tui`, now proves dark → light → dark → light → dark updates in one real, offline Pi process using its native file watcher. It observes foreground, accent, and panel ANSI colors without calling `setTheme`, sending a prompt, reloading Pi, or receiving terminal theme notifications. Temporary HOME/agent directories contain no credentials.
- Both existing guard rule suites pass.
- `node platforms/omarchy/tests/test_notify.mjs` validates Kitty/WezTerm routing, tmux framing and control-character sanitization without sending a notification.
- Credential/runtime directories remain real local directories; authored links resolve into `~/.dotfiles`.

Local logs, audit JSON and backups are under `~/.local/state/dotfiles-migration/`, not in the repository. `pi-nvim-backup-path` records the pre-migration settings backup. No commit or push has been made.
