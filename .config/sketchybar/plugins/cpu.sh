#!/bin/sh

CPU=$(top -l 1 -s 0 -n 0 | grep "CPU usage" | awk '{printf "%.0f", $3 + $5}')
sketchybar --set "$NAME" label="${CPU}%"
