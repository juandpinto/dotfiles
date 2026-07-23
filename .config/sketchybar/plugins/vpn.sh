#!/bin/sh

DARK=$(defaults read -g AppleInterfaceStyle 2>/dev/null)
# Everforest green: dark #a7c080 / light #8da101
GREEN=$([ "$DARK" = "Dark" ] && echo "0xffa7c080" || echo "0xff8da101")

# Primary: macOS Network Configuration (covers NordVPN, IKEv2, WireGuard.app, L2TP, etc.)
VPN_NAME=$(scutil --nc list 2>/dev/null \
  | awk -F'"' '/\(Connected\)/ {print $2; exit}')

# Fallback: utun interface with an IPv4 address assigned (catches VPNs that bypass scutil)
if [ -z "$VPN_NAME" ]; then
  if ifconfig 2>/dev/null \
      | awk '/^utun[0-9]+:/ {iface=$1} /inet / && iface {print $2; iface=""}' \
      | grep -qE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'; then
    VPN_NAME="VPN"
  fi
fi

if [ -n "$VPN_NAME" ]; then
  sketchybar --set "$NAME" drawing=on icon.color=$GREEN
else
  sketchybar --set "$NAME" drawing=off
fi
