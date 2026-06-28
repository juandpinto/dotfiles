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
  # Catppuccin green / VS Code: 0xffb5cea8 (dark) / 0xff098658 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xffa6e3a1" || echo "0xff40a02b")
elif [ "$PERCENTAGE" -le 20 ]; then
  # Catppuccin red / VS Code: 0xfff44747 (dark) / 0xffa31515 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xfff38ba8" || echo "0xffd20f39")
elif [ "$PERCENTAGE" -le 40 ]; then
  # Catppuccin peach / VS Code: 0xffce9178 (dark) / 0xff795e26 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xfffab387" || echo "0xfffe640b")
else
  # Catppuccin text / VS Code: 0xffd4d4d4 (dark) / 0xff343434 (light)
  COLOR=$([ "$DARK" = "Dark" ] && echo "0xffcdd6f4" || echo "0xff4c4f69")
fi

sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%" icon.color=$COLOR label.color=$COLOR
