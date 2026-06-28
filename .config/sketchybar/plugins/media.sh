#!/bin/sh

PLAYER_STATE=$(osascript -e '
  tell application "System Events"
    if (name of processes) contains "Music" then
      tell application "Music" to player state as string
    else
      "stopped"
    end if
  end tell' 2>/dev/null)

if [ "$PLAYER_STATE" = "playing" ]; then
  TRACK=$(osascript -e 'tell application "Music" to name of current track' 2>/dev/null)
  if [ -n "$TRACK" ]; then
    if [ ${#TRACK} -gt 25 ]; then
      TRACK="${TRACK:0:24}…"
    fi
    sketchybar --set "$NAME" label="$TRACK" drawing=on
    exit 0
  fi
fi

sketchybar --set "$NAME" drawing=off
