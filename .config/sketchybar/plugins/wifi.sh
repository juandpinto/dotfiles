#!/bin/sh

# Fast connection check (~1ms)
IP=$(ipconfig getifaddr en0 2>/dev/null)

if [ -z "$IP" ]; then
# Catppuccin / VS Code disconnected colors:
#   mocha red #f38ba8 → 0xfff38ba8 | latte red #d20f39 → 0xffd20f39
#   vscode: 0xfff44747 (dark) / 0xffa31515 (light)
DISCONNECTED_COLOR=$(defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && echo "0xfff38ba8" || echo "0xffd20f39")
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

# Catppuccin / VS Code connected colors:
#   mocha blue #89b4fa → 0xff89b4fa | latte blue #1e66f5 → 0xff1e66f5
#   vscode: 0xff569cd6 (dark) / 0xff007acc (light)
CONNECTED_COLOR=$(defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark && echo "0xff89b4fa" || echo "0xff1e66f5")
sketchybar --set "$NAME" icon="$ICON" icon.color=$CONNECTED_COLOR label.drawing=off
