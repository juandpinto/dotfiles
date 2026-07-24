#!/bin/bash

# Single source of truth for "is macOS in dark or light mode right now, and
# did it just change". Run as a LaunchAgent (see
# ~/Library/LaunchAgents/com.juanpinto.appearance-watcher.plist) so it's one
# long-lived, auto-restarting process instead of the four independent
# per-tool polling loops this replaced (sketchybar, tmux, btop each ran their
# own `defaults read` poll; nvim's auto-dark-mode.nvim did too).
#
# Writes the current appearance to $STATE_FILE on every change so other
# consumers (e.g. nvim, see everforest.lua) can cheaply read a file instead
# of spawning their own `defaults read`. Also directly triggers the
# tools below that don't have their own way to pick up a live change.
#
# sketchybar and tmux each already re-detect appearance fresh whenever they
# reload/start (sketchybarrc's own `defaults read` at the top; tmux.conf's
# `if-shell` flavor check) -- reloading/sourcing them here is enough, no
# separate "sync file" needed for those two. btop is different: it only
# reads color_theme from btop.conf passively, so that file must be kept in
# sync unconditionally (not just gated on btop currently running), or a
# fresh `btop` launch would load a stale theme. starship is simpler still:
# it re-execs as a subprocess and re-reads its config file fresh on every
# single prompt render, so keeping ~/.config/starship.toml in sync here is
# enough on its own -- the very next prompt draw already reflects the
# change, no reload signal needed.

STATE_FILE="$HOME/.cache/appearance"
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
BTOP_CONF="$HOME/.config/btop/btop.conf"
STARSHIP_CONF="$HOME/.config/starship.toml"
STARSHIP_DIR="$HOME/.config/starship"

mkdir -p "$(dirname "$STATE_FILE")"

react() {
  local raw="$1" # "Dark" or "" (empty means light -- see detectors elsewhere
  local mode="light"
  [ "$raw" = "Dark" ] && mode="dark"

  echo "$(date '+%Y-%m-%d %H:%M:%S') -> $mode"
  echo "$mode" >"$STATE_FILE"

  # sketchybar: full reload re-derives its own colors from `defaults read`.
  pgrep -x sketchybar &>/dev/null && sketchybar --reload &>/dev/null

  # tmux: sourcing the config re-runs its own appearance if-shell check.
  tmux info &>/dev/null && tmux source-file "$TMUX_CONF" &>/dev/null

  # btop: keep the config file in sync regardless of whether btop is
  # currently running (so a later fresh launch picks the right theme), but
  # only signal a live hot-reload if a btop process actually exists.
  local btop_theme="everforest-light-medium"
  [ "$mode" = "dark" ] && btop_theme="everforest-dark-medium"
  if [ -f "$BTOP_CONF" ]; then
    sed -i '' -E "s/^color_theme = \".*\"/color_theme = \"${btop_theme}.theme\"/" "$BTOP_CONF"
  fi
  pgrep -x btop &>/dev/null && pkill -USR2 -x btop 2>/dev/null

  # starship: no live process to signal -- just keep the config file in
  # sync unconditionally, same as btop.conf above. The next prompt render
  # (any new shell, or the next command in an already-open one) picks it
  # up automatically since starship re-reads this file every time.
  if [ -f "$STARSHIP_CONF" ]; then
    cp "$STARSHIP_DIR/everforest-${mode}.toml" "$STARSHIP_CONF"
  fi
}

PREV=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
react "$PREV" # sync state file + all tools once on startup

while true; do
  sleep 1
  MODE=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
  if [ "$MODE" != "$PREV" ]; then
    react "$MODE"
    PREV="$MODE"
  fi
done
