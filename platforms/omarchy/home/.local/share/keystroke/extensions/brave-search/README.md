# Brave web search

We use `s <query>` in Keystroke to open Brave Search in our default browser. On this machine the HTTPS handler is Brave Origin (`brave-origin.desktop`); no special browser support or browser API is needed.

- `s Asahi Linux` then Enter opens `https://search.brave.com/search?q=Asahi%20Linux`.
- Ctrl+Enter copies the search URL instead.
- The prefix can be renamed under this extension's settings.
- This searches the web, not browser history or bookmarks.

## Privacy and dependencies

The extension only constructs a URL in memory. It does not read browser profiles, history, bookmarks, clipboard, or other files, does not run a background process, does not download anything, and does not make network requests while we type. Only explicit activation opens the URL through Keystroke's `url` effect and `xdg-open`; the browser then sends the query to Brave Search normally. The query is not included in a persisted frecency ID.

There are no dependencies beyond the existing Keystroke host and a default HTTPS browser. Query text is URL-encoded and never inserted into a shell command. Empty queries produce a disabled hint.

## Deployment and checks

The extension directory is linked as a whole from our dotfiles into `~/.local/share/keystroke/extensions/brave-search`. We do not modify the upstream Keystroke checkout. Enable `providers.brave-search.enabled` in `~/.config/omarchy/keystroke.json`; only one provider should own prefix `s`.

Run Keystroke's `check-extensions` command against this directory to validate the manifest, lint QML, and run the unit tests. Tests never open a browser or send a query over the network.
