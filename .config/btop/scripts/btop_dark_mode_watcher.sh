#!/bin/bash

# Watches for macOS appearance changes and flips btop's catppuccin theme to
# match (mocha for dark, latte for light) — mirrors tmux's
# tmux_dark_mode_watcher.sh.
#
# btop has no built-in system-appearance detection, and it only ever picks up
# a new color_theme from btop.conf on startup — unless you send it SIGUSR2,
# which triggers btop's own "hot reload config" path (same as pressing
# Ctrl+R inside it). This script edits color_theme in btop.conf and signals
# every running btop process whenever AppleInterfaceStyle changes.
#
# Launched from the `btop` shell function (see .zshrc) whenever btop starts,
# de-duping itself via a pidfile lock like the tmux watcher. Exits on its own
# once no btop process is left running.

LOCK="${TMPDIR:-/tmp}/btop_dark_mode_watcher.lock"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi
echo $$ >"$LOCK"
trap 'rm -f "$LOCK"' EXIT

BTOP_CONF="$HOME/.config/btop/btop.conf"

write_theme() {
  local theme="catppuccin_latte"
  [ "$1" = "Dark" ] && theme="catppuccin_mocha"
  sed -i '' -E "s/^color_theme = \".*\"/color_theme = \"${theme}.theme\"/" "$BTOP_CONF"
}

PREV=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
# Sync the config file to the current appearance so a freshly-started btop
# picks the right theme on its own on startup — no signal needed for that.
# Signalling here would race against the just-launched btop installing its
# own SIGUSR2 handler: if it loses that race, the signal's default
# disposition (terminate) kills it instead of triggering a hot reload.
write_theme "$PREV"

while true; do
  sleep 2
  pgrep -x btop &>/dev/null || exit 0

  MODE=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
  if [ "$MODE" != "$PREV" ]; then
    write_theme "$MODE"
    # Only reached after at least one sleep, so btop has long since finished
    # installing its signal handler — safe to hot-reload it live here.
    pkill -USR2 -x btop 2>/dev/null
    PREV="$MODE"
  fi
done
