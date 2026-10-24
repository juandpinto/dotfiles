# Background crossfade

User-owned clone of `omarchy.background`, created with `omarchy plugin clone omarchy.background`. It replaces the diagonal reveal with an **1-second opacity crossfade**, using `Easing.InOutSine`. The old image stays opaque while the incoming image fades in, avoiding a fade through black. Image loading, monitor remapping, crop behavior, click actions, theme handoff and native background IPC are retained. The one-minute shuffle timer is independent and unchanged.

## Deployment and verification

The Linux linker links this complete directory into `~/.config/omarchy/plugins/jdpinto.background`; files inside remain ordinary files. The live `shell.json` remains GUI/CLI-managed, not linked into the repository. Validate the source directory with `omarchy plugin validate`.

Enable with `omarchy plugin enable jdpinto.background`. Omarchy's current dynamic plugin hot reload can retain cached QML; ask before a brief `omarchy restart shell` when a rescan does not apply changes. Do not restart a locked shell. `omarchy-shell background inspect` reports the transition, duration, progress and image handoff after the new component is loaded. Disable the clone with `omarchy plugin disable jdpinto.background` to restore the built-in renderer.

## Upstream maintenance

Based on the installed Omarchy background plugin version `1.0.0`, copied on 2026-10-16. The original `Background.qml` SHA-256 is `6135a06b4c17c9a5a251053c294a657ecd80eb3a339f6eea146455b3925fd65b`.

Clones do not automatically inherit future package fixes. Compare `/usr/share/omarchy/shell/plugins/background/` after relevant Omarchy updates and carry forward upstream changes deliberately. Keep the custom delta small: remove the reveal-mask effects/shapes, animate incoming opacity, use the slower easing/duration, and retain the read-only inspect helper. Never edit the package-owned source.
