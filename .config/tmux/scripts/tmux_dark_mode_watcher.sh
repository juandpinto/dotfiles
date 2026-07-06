#!/bin/bash

# Watches for macOS appearance changes and flips tmux's catppuccin flavor to
# match (mocha for dark, latte for light) — mirrors sketchybar's
# dark_mode_watcher.sh.
#
# tmux 3.6+ has native client-dark-theme/client-light-theme hooks, but they
# only fire when the terminal reports appearance changes in-band (via the
# DECRQM 2031 / OSC theme-change protocol). WezTerm doesn't send that, so the
# hooks never trigger in practice — hence this poll-based fallback.
#
# Launched from tmux.conf with run-shell -b on every config load/reload, so
# it de-dupes itself via a pidfile lock (a pgrep-based guard in tmux.conf
# doesn't work here: tmux runs the test through a wrapper shell whose own
# command line contains the search pattern, causing a permanent false-positive
# self-match). Exits on its own once the tmux server it was started for goes
# away.

LOCK="${TMPDIR:-/tmp}/tmux_dark_mode_watcher.lock"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi
echo $$ >"$LOCK"
trap 'rm -f "$LOCK"' EXIT

# Re-sourcing the whole config (rather than just poking @catppuccin_flavor and
# re-running the plugin) matters: catppuccin/tmux's color variables are set
# with tmux's "only if unset" flag, so flipping the flavor alone wouldn't
# actually recolor anything already-set. tmux.conf handles the reset dance
# (see its "Catppuccin" section) — this script just needs to trigger it.
TMUX_CONF="$HOME/.config/tmux/tmux.conf"
PREV=$(defaults read -g AppleInterfaceStyle 2>/dev/null)

while true; do
  sleep 2
  tmux info &>/dev/null || exit 0

  MODE=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
  if [ "$MODE" != "$PREV" ]; then
    tmux source-file "$TMUX_CONF"
    PREV="$MODE"
  fi
done
