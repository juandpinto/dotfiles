#!/bin/sh

DARK=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
# Everforest purple: dark #d699b6 / light #df69ba
MAUVE=$([ "$DARK" = "Dark" ] && echo "0xffd699b6" || echo "0xffdf69ba")

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
