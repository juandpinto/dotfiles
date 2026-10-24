# Lock screen (stranded-lock fix)

User-owned clone of `omarchy.lock`, created with `omarchy plugin clone omarchy.lock`. It carries upstream PR #14978 (merged 2026-10-11, not yet in the installed package): lock-state decisions call `currentlyLocked()` and read the state afresh instead of trusting a property binding. Quickshell 0.3.2's `WlSessionLock::unlock()` never emits `lockStateChanged`, so the binding could keep reporting "locked" after an unlock, and a lock request before suspend then took that as done and never locked the session. `LockView.qml` is unmodified; only `Service.qml` differs.

## Deployment and verification

The Linux linker links this complete directory into `~/.config/omarchy/plugins/jdpinto.lock`; files inside remain ordinary files. Enable with `omarchy plugin enable jdpinto.lock` (which disables `omarchy.lock`). Validate the source directory with `omarchy plugin validate`. Do not restart a locked shell.

## Upstream maintenance

Based on the installed Omarchy lock plugin version `1.0.0` (Omarchy 4.0.3rc4). The original `Service.qml` SHA-256 is `79fe6348955047cd18183a4e2f5bbb020289a62d2f761ede13e71fb58d784f3b`. Remove this clone (`omarchy plugin disable jdpinto.lock`, then re-enable `omarchy.lock`) once `/usr/share/omarchy/shell/plugins/lock/Service.qml` ships `currentlyLocked()`. Until then, compare that file after Omarchy updates and carry upstream changes forward deliberately; never edit the package-owned source.
