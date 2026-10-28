# Herdr trial and desktop integration

Linux uses Herdr as a trial while retaining tmux. Shared Neovim changes preserve existing Mac/tmux/WezTerm behavior: inner tmux takes priority; Herdr is selected only with its inherited pane/socket environment and no inner tmux. We do not emulate tmux commands or install a polling daemon.

## Pi and sidebar

Install the official managed hook with `herdr integration install pi`. Herdr owns `~/.pi/agent/extensions/herdr-agent-state.ts`; it is not an authored dotfiles link. It reports working/settled lifecycle and resumable conversation references over a local socket. Explicit blocked states require cooperating extensions; screen detection remains relevant for custom approval dialogs. Existing Pi sessions need `/reload`; fresh sessions discover the hook automatically.

Only `~/.config/herdr/config.toml` is linked, from the shared `.config/herdr/config.toml` source used by both Mac and Linux. The old overlay source path remains a compatibility symlink so existing Linux links keep working until `link.sh` is rerun. Pi-specific sidebar rows show the row's number and agent/state, the pi session name (the terminal title without its `π -` prefix and directory suffix), and the workspace. Herdr sockets, logs, session layouts, histories, and credentials stay local. The host terminal title includes the active tab. Tabs are named automatically, tmux-style, by the shared [labels plugin](../../.config/herdr/labels/README.md), which also supplies the sidebar numbers and pi titles; it reacts to Herdr's events rather than polling.

## Neovim and persistent processes

`lua/juan/herdr.lua` is a small native socket client, shared by the Slime target, Sidekick backend and split/focus mappings. It uses explicit inherited caller/target IDs, bounded requests, and no automatic retry of a mutation after an ambiguous timeout. Targets are scoped to the current server; automatic REPL discovery is limited to an unambiguous IPython process in the caller's tab. Agent panes are not guessed as REPL targets.

- `<leader>rr` starts IPython in a new sibling pane when necessary, reuses an existing target, and never types a launch command into an already-running REPL or another foreground command. Outside projects, Herdr uses the installed personal IPython tool environment rather than downloading a bare uvx environment without the startup dependencies.
- `:SlimeConfig` chooses a target explicitly. Cell/selection sends retain the existing Python formatter and bracketed-paste safeguards. Enter and Ctrl+C/D/L use Herdr's negotiated key encoding. `<leader>rf` focuses the chosen target.
- `<leader>tv` splits Herdr in the file directory; inside tmux it retains the existing tmux operation. It does not guess another running multiplexer when neither environment is present.
- Sidekick registers a Herdr backend through its session API, retaining selection/file/prompt formatting. `<leader>aa` and `<leader>aP` focus an external Herdr agent pane, rather than toggling an embedded Neovim terminal. Detach only removes the editor association; it does not stop the pane or agent. New sessions are real Herdr splits and survive an editor exit.

The installed Sidekick version accepts only `tmux`/`zellij` in its global `cli.mux.backend` setting, even though its session registry can hold our Herdr adapter. We therefore leave its built-in mux disabled in Herdr and create explicit registered Herdr session states through the mapped actions above, including selection/context/prompt sends. Do not set the global option to `herdr`, suppress its validator, or relabel the adapter as tmux. For creating persistent Herdr agents, use the mapped actions; upstream commands that create an unattached session bypass this routing. Commands operating on an already-attached Herdr session can reuse it normally.

The standard Bash hook supplies inner CWD/prompt markers in Herdr even when Kitty hosts its client. Existing shells need a new shell or `source ~/.bashrc`. Existing Neovim processes should be restarted when convenient to load the adapters; no real editor, REPL or agent is forcibly restarted.

IPython's execution timer and quiet queued-input hooks remain standard terminal/TTY code. Its OSC title is available to Herdr, but the changing timer is not automatically copied into Herdr pane-border metadata. Image rendering still uses standard Kitty graphics rather than the removed/newer Herdr-specific graphics API. Real plot resize/reattach acceptance remains a separate user-workflow check.

## Widget launcher

The `jdpinto.herdr` wrapper inherits the installed `jankeesvw.herdr` UI and overrides only opening/focusing sessions. `herdr-widget-open` uses `xdg-terminal-exec`, so the configured Kitty default wins instead of the upstream helper's Foot preference. Existing windows are reused, named/local/remote routing and demo-mode no-op behavior are retained, and the upstream Git worktree remains untouched. Keep the upstream plugin installed; update it normally and revalidate the wrapper after relevant upstream interface changes.

`omarchy plugin disable jdpinto.herdr` restores the upstream widget. The bar's existing position and per-widget settings are carried into the replacement.

## Blur and active border

Kitty retains opacity 0.93 and requests blur with `background_blur 10`. On Hyprland, the compositor determines actual blur strength: size 4, two passes, restricted to Kitty and the app-ids Omarchy's launchers give terminal windows (`org.omarchy.*` such as Herdr, Yazi and btop, and `TUI.*`). Other applications retain their previous no-blur behavior. This is a gentle approximation, not a claim that Wayland and macOS blur-radius units are identical.

The user look-and-feel override preserves rounding 8 and inactive dimming 0.15. Both normal and grouped active borders use the Mac's exact red `#e67e80`; inactive borders are transparent. Hyprland's native `w[1]` selector removes borders from single-window workspaces. Multi-window geometry remains stable when focus moves; no event watcher is needed. Existing gaps and border thickness are retained.

## Verification

Run from the dotfiles root:

```bash
node platforms/omarchy/tests/test_herdr_port.mjs
node platforms/omarchy/tests/test_herdr_widget_launcher.mjs
```

The first test creates a named server under a private temporary HOME, a disposable IPython profile and synthetic cells. It checks real Slime delivery, queued multiline cells, interruption/recovery, target discovery/focus and stale/self guards; Sidekick's public backend API and lifecycle are exercised with a mocked transport. Fresh editor processes check Mac/WezTerm and inner-tmux precedence, wait for Sidekick's scheduled validators and fail on error notifications. The regression first reproduced the rejected global `herdr` option; adapter tests also exercise mapped creation/focus/context/prompt routes, cancellation and capture of context before opening a picker. The installed official Pi hook is tested against a fake local socket, without sending model prompts or using real session histories. Only the private test server is stopped afterward.

Launcher checks replace all launching/window/Herdr commands with fixtures; they never open a real session or dial SSH. Backups from this change are under `~/.local/state/dotfiles-migration/backups/herdr-desktop.*`. Software versions are not upgraded as part of this configuration work.
