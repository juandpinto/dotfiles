#!/bin/sh

# Fast connection check (~1ms)
IP=$(ipconfig getifaddr en0 2>/dev/null)

if [ -z "$IP" ]; then
# Everforest / VS Code disconnected colors:
#   dark red #e67e80 → 0xffe67e80 | light red #f85552 → 0xfff85552
#   vscode: 0xfff44747 (dark) / 0xffa31515 (light)
DISCONNECTED_COLOR=$(defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && echo "0xffe67e80" || echo "0xfff85552")
  sketchybar --set "$NAME" icon="󰤭" icon.color=$DISCONNECTED_COLOR label.drawing=off
  exit 0
fi

# Connected — get RSSI from system_profiler (runs every 30s, ~3s acceptable)
RSSI=$(system_profiler SPAirPortDataType 2>/dev/null \
  | awk '/Current Network Information:/{found=1} found && /Signal \/ Noise/{gsub(/[^0-9-]/," "); for(i=1;i<=NF;i++) if($i~/^-[0-9]+$/){print $i; exit}}')

[ -z "$RSSI" ] && RSSI=-50

if   [ "$RSSI" -ge -50 ]; then ICON="󰤨"
elif [ "$RSSI" -ge -60 ]; then ICON="󰤥"
elif [ "$RSSI" -ge -70 ]; then ICON="󰤢"
else                           ICON="󰤟"
fi

# Everforest / VS Code connected colors:
#   dark blue #7fbbb3 → 0xff7fbbb3 | light blue #3a94c5 → 0xff3a94c5
#   vscode: 0xff569cd6 (dark) / 0xff007acc (light)
CONNECTED_COLOR=$(defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && echo "0xff7fbbb3" || echo "0xff3a94c5")
sketchybar --set "$NAME" icon="$ICON" icon.color=$CONNECTED_COLOR label.drawing=off
