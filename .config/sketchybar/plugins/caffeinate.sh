#!/bin/sh

DARK=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
# Catppuccin mauve: mocha #cba6f7 / latte #8839ef
MAUVE=$([ "$DARK" = "Dark" ] && echo "0xffcba6f7" || echo "0xff8839ef")

get_caffeinate_pid() {
  # pmset reads kernel power assertions — catches any caffeinate, not just bar-started ones
  pmset -g assertions 2>/dev/null \
    | grep -i "caffeinate" \
    | awk '{print $2}' \
    | tr -d '(' \
    | head -1
}

if [ "$SENDER" = "caffeinate_toggle" ]; then
  PID=$(get_caffeinate_pid)
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null
  else
    caffeinate -di &
    disown
  fi
fi

PID=$(get_caffeinate_pid)
if [ -n "$PID" ]; then
  sketchybar --set "$NAME" drawing=on icon.color=$MAUVE
else
  sketchybar --set "$NAME" drawing=off
fi
