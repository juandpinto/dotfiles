#!/bin/sh

GPU=$(ioreg -r -d 1 -w 0 -c IOAccelerator 2>/dev/null \
  | grep "PerformanceStatistics" \
  | grep -oE '"Device Utilization %"=[0-9]+' \
  | grep -oE '[0-9]+$')

[ -z "$GPU" ] && GPU=0
sketchybar --set "$NAME" label="${GPU}%"
