# Herdr default-terminal wrapper

This tiny QML wrapper inherits the installed `jankeesvw.herdr` panel and overrides its open/focus actions. The UI, polling, agent states, pinning and destructive-action confirmations remain upstream code. The user launcher goes through `xdg-terminal-exec`, currently Kitty, instead of explicitly preferring Foot. No upstream Git files are patched.

Keep `~/.config/omarchy/plugins/jankeesvw.herdr` installed. Omarchy loads this wrapper through its live plugin path, where the relative upstream import resolves. The Linux linker links the whole wrapper directory; files inside are not individual symlinks. Enable with `omarchy plugin enable jdpinto.herdr`; disabling it restores the upstream widget through `omarchy.clonedFrom`.

The launcher validates session/pane/machine identifiers, resolves remote targets from Herdr's enabled catalog, reuses an existing window when possible, and respects the upstream demo flag. It never stops sessions or signals server PIDs. Upstream interface changes to `Panel.qml` may require adjusting the two small overrides; run the launcher tests and validate the loaded widget after updates.
