# Lid awake bar icon

Shows a laptop icon while `lid-awake.service` is running, meaning the laptop keeps running with the lid closed. Clicking it runs `lid-awake off`. The icon is hidden while lid awake is off; turn it on with `Super+Ctrl+Shift+I` or `lid-awake on`.

The widget asks systemd for the service state when loaded, when `lid-awake` sends `omarchy-shell jdpinto.lid-awake refresh`, and every 30 s as a fallback. The script, service and guards are described in the overlay README's "Lid awake" section. The Linux linker links this whole directory. Enable it with `omarchy plugin enable jdpinto.lid-awake`.
