#!/usr/bin/env bash

DARK=$(defaults read -g AppleInterfaceStyle 2>/dev/null)

# Per-space Everforest accent colors — dark (light pastels) / light
# (saturated). Everforest only has 7 named accents vs Catppuccin's 9 used
# here, so spaces 7-9 (lavender/mauve/pink) all reuse the purple accent.
case "$1" in
  1) DK="0xffe67e80"; LT="0xfff85552" ;;  # red
  2) DK="0xffe69875"; LT="0xfff57d26" ;;  # orange
  3) DK="0xffdbbc7f"; LT="0xffdfa000" ;;  # yellow
  4) DK="0xffa7c080"; LT="0xff8da101" ;;  # green
  5) DK="0xff83c092"; LT="0xff35a77c" ;;  # aqua
  6) DK="0xff7fbbb3"; LT="0xff3a94c5" ;;  # blue
  7) DK="0xffd699b6"; LT="0xffdf69ba" ;;  # purple
  8) DK="0xffd699b6"; LT="0xffdf69ba" ;;  # purple
  9) DK="0xffd699b6"; LT="0xffdf69ba" ;;  # purple
  *) DK="0xffd3c6aa"; LT="0xff5c6a72" ;;  # fg fallback
esac

SPACE_COLOR=$([ "$DARK" = "Dark" ] && echo "$DK" || echo "$LT")
# Active pill text: dark-mode accents are light pastels → dark base; light-
# mode accents are saturated/dark → white
PILL_TEXT=$([ "$DARK" = "Dark" ] && echo "0xff2d353b" || echo "0xffffffff")

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
