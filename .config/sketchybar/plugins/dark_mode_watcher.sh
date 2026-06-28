#!/bin/bash

# Watches for macOS appearance changes and reloads SketchyBar.
# Launched from sketchybarrc with nohup/disown so it persists across reloads.
PREV=$(defaults read -g AppleInterfaceStyle 2>/dev/null)

while true; do
  sleep 2
  MODE=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
  if [ "$MODE" != "$PREV" ]; then
    sketchybar --reload
    PREV="$MODE"
  fi
done
