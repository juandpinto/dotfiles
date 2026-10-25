# Charge limit bar icon

Shows a battery-heart icon while the Apple Silicon battery charge limit is below 100%, as a reminder that the battery will stop charging at 80% (`omarchy battery charge limit 80`). Clicking it opens a terminal that runs `omarchy battery charge limit 100`, which asks for the sudo password. The icon is hidden at 100%.

The widget reads `charge_control_end_threshold` every 10 s, because Omarchy's command cannot notify the bar. Asahi keeps the limit across reboots, so the icon reappears after a reboot if the limit is still on. The Linux linker links this whole directory. Enable it with `omarchy plugin enable jdpinto.charge-limit`.
