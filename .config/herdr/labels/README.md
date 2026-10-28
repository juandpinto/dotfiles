# labels: sidebar numbers, clean pi titles, and automatic tab names for Herdr

Herdr can jump to an agent, workspace, or tab by number, but its expanded sidebar does not show the numbers, and its tabs show either a name or a number, never both. This plugin fills both gaps from the outside, through display values Herdr already accepts from plugins. It does three things:

| What           | Where it shows                                 | Value                                                                                                                     |
| -------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `$idx` token   | Spaces and Agents rows (`[ui.sidebar.*].rows`) | The row's 1-based position, which is what `prefix+w` + digit, `switch_workspace`, and `focus_agent` jump to               |
| `$title` token | Agents rows                                    | The pane's terminal title; pi's `π - <session> - <dir>` becomes `<session>`                                               |
| Tab labels     | The tab bar                                    | `<position>:<name>`, like tmux's `#I:#W`; the name is the tab's agent session, the program in its title, or one you typed |

Herdr has no built-in index token and has declined to add one (herdrdev/herdr#2046, #3958), so the numbers come from a plugin or not at all.

## Setup

The plugin is registered by path once per machine, like `lastfocus`:

```sh
herdr plugin link ~/.dotfiles/.config/herdr/labels
```

Herdr starts the daemon when its server starts. After the first `plugin link` on a machine whose server is already running, start it once by hand or restart Herdr:

```sh
cd ~/.dotfiles/.config/herdr/labels && HERDR_SOCKET_PATH=~/.config/herdr/herdr.sock \
    HERDR_PLUGIN_STATE_DIR=~/.local/state/herdr/plugins/labels \
    uv run --offline --no-project --python python3 labels.py daemon --ensure
```

The tokens only appear where the shared `../config.toml` asks for them. It puts `$idx` in front of the status icon on every Spaces and Agents row, and `$title` on the second row of pi agents. Herdr separates tokens with ` · ` except after the status icon, so a row reads `2 · ● .dotfiles`. The tab bar needs no configuration.

Requires Python 3.9 or newer as `python3` on `PATH`.

## How it works

`labels.py daemon --ensure` is the plugin's startup hook. It starts one detached daemon per Herdr server, keyed by the server's socket path, and is idempotent: a file lock means a second `--ensure` does nothing while a daemon is alive. The daemon subscribes to the events that can reorder the sidebar, retitle a pane, or rename a tab, and after each burst of them reads `session.snapshot` and derives the three kinds of values from it. It only writes values that differ from what the snapshot already holds, so a quiet session costs one snapshot read per event and no writes. The daemon exits when the server's socket disappears.

A daemon is needed rather than the manifest's `[[events]]` hooks because swapping or resizing panes only emits `layout.updated`, which Herdr keeps away from plugin hooks as high-volume. Hooks would leave the agent numbers stale after a swap.

**Numbers.** Agents are numbered in the order of `session.snapshot`'s agent list, which is the order the Agents panel draws and the agent shortcuts use while the panel is sorted by space (`agent_panel_sort = "spaces"`, the header reads "grouped"). Workspaces are numbered in sidebar order: creation order, except that the checkouts of one Git repository are grouped with the main checkout first and its worktrees after it. Numbers are not capped at 9; a `{ gt = 9, hide = true }` rule on the token can hide the ones without a shortcut.

**Titles.** Pi titles its terminal `π - <session> - <dir>`, or `π - <dir>` while the session is unnamed, and that string is not configurable. `$title` is the session name alone, empty while unnamed, so the row disappears rather than repeating the directory. For other agents `$title` is the stripped terminal title unchanged. Pi's title is left alone at the source, so the tmux `automatic-rename-format` on the Mac, which matches the `π -` prefix, keeps working.

**Tabs.** Every label starts with the tab's position in its workspace, which is what `prefix` + digit (`switch_tab`) jumps to, so `2:bash` is the second tab. Herdr has no label format of its own, so the plugin writes the number into the label and rewrites it whenever tabs are added, closed, or moved. A tab with no name is just its number, which looks like Herdr's default.

A tab is named after its first agent pane, else its first pane with a title. Pi panes contribute their session name, or `pi` while unnamed; other panes contribute their title up to its first separator, so `bash - ~/.dotfiles` becomes `bash`, `Yazi: notes` becomes `Yazi`, and `init.lua (~/.config/nvim) - NVIM` becomes `init.lua`. Automatic names are cut at 15 characters with `…`, as the tmux format did.

The plugin remembers the label it last wrote to each tab in a state file under `HERDR_PLUGIN_STATE_DIR`. Any other label was typed by hand (or is Herdr's default for a new tab). The plugin keeps a typed name for good, without the index the rename prompt starts with, so editing `2:bash` to `2:notes` or to `notes` both give `2:notes`, and it keeps that name numbered as tabs move. Herdr has no way to drop a custom label, so renaming a tab to just its number hands it back to automatic naming.

## Limitations

- Numbers follow the "grouped" agent order. Clicking the Agents header switches the panel to "priority", which both the panel and the agent shortcuts follow but the numbers do not. Click it back. The same applies to plugins that filter or sort the panel through `agent.view.set`; none are installed here.
- A collapsed worktree group hides its worktrees in the Spaces panel, but Herdr does not expose that per-client state, so workspace numbers below a collapsed group run ahead of the sidebar by the number of hidden rows.
- Herdr forgets tokens on a server restart; the startup hook publishes them again. Tab labels persist with the session, and so does the plugin's record of the labels it wrote and the names you typed.
- Herdr's `{tab}` token in `window_title` is the label, so the window title includes the number too: `host: .dotfiles · 2:bash`.
- Only pi's title format is parsed. Other agents' titles are passed through as they are.

## Tests

`tests/test_labels.py` checks the pure functions, then starts a throwaway headless Herdr session, starts the daemon the way the startup hook does, changes the layout through the CLI and checks the numbers, titles, and tab labels it publishes, including that a tab named by hand keeps its name, gets renumbered, and can be handed back, and that the daemon exits when the server stops. When `pi` is on `PATH` it also starts a real pi agent, offline and with a scratch session directory, to check agent numbering. It never touches the default session.

```sh
uv run --no-project tests/test_labels.py
```
