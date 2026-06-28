#!/usr/bin/env bash

DARK=$(defaults read -g AppleInterfaceStyle 2>/dev/null)

# Per-space Catppuccin accent colors — mocha (light) / latte (dark/saturated)
case "$1" in
  1) DK="0xfff38ba8"; LT="0xffd20f39" ;;  # red
  2) DK="0xfffab387"; LT="0xfffe640b" ;;  # peach
  3) DK="0xfff9e2af"; LT="0xffdf8e1d" ;;  # yellow
  4) DK="0xffa6e3a1"; LT="0xff40a02b" ;;  # green
  5) DK="0xff94e2d5"; LT="0xff179299" ;;  # teal
  6) DK="0xff89b4fa"; LT="0xff1e66f5" ;;  # blue
  7) DK="0xffb4befe"; LT="0xff7287fd" ;;  # lavender
  8) DK="0xffcba6f7"; LT="0xff8839ef" ;;  # mauve
  9) DK="0xfff5c2e7"; LT="0xffea76cb" ;;  # pink
  *) DK="0xffcdd6f4"; LT="0xff4c4f69" ;;  # text fallback
esac

SPACE_COLOR=$([ "$DARK" = "Dark" ] && echo "$DK" || echo "$LT")
# Active pill text: mocha accents are light → dark base; latte accents are dark → white
PILL_TEXT=$([ "$DARK" = "Dark" ] && echo "0xff1e1e2e" || echo "0xffffffff")

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set $NAME \
    icon.color=$PILL_TEXT \
    label.color=$PILL_TEXT \
    background.color=$SPACE_COLOR \
    background.border_width=0
else
  sketchybar --set $NAME \
    icon.color=$SPACE_COLOR \
    label.color=$SPACE_COLOR \
    background.color=0x00000000 \
    background.border_width=0
fi
