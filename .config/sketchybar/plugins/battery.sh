#!/bin/sh

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

case "${PERCENTAGE}" in
  9[0-9]|100) ICON=""  ;;
  [6-8][0-9])  ICON=""  ;;
  [3-5][0-9])  ICON=""  ;;
  [1-2][0-9])  ICON=""  ;;
  *)           ICON=""  ;;
esac

DARK=$(defaults read -g AppleInterfaceStyle 2>/dev/null)

if [[ "$CHARGING" != "" ]]; then
  # Everforest green / VS Code: 0xffb5cea8 (dark) / 0xff098658 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xffa7c080" || echo "0xff8da101")
elif [ "$PERCENTAGE" -le 20 ]; then
  # Everforest red / VS Code: 0xfff44747 (dark) / 0xffa31515 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xffe67e80" || echo "0xfff85552")
elif [ "$PERCENTAGE" -le 40 ]; then
  # Everforest orange / VS Code: 0xffce9178 (dark) / 0xff795e26 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xffe69875" || echo "0xfff57d26")
else
  # Everforest fg / VS Code: 0xffd4d4d4 (dark) / 0xff343434 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xffd3c6aa" || echo "0xff5c6a72")
fi

sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%" icon.color=$COLOR label.color=$COLOR
