#!/usr/bin/env bash
# Isolated tests: logind, systemd, the shell and real batteries are all mocked.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$root/home/.local/bin/lid-awake"
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/ps/ac" "$fixture/ps/usb" "$fixture/ps/bat"
echo Mains > "$fixture/ps/ac/type"
echo USB > "$fixture/ps/usb/type"
echo 1 > "$fixture/ps/usb/online"
echo Battery > "$fixture/ps/bat/type"

mock() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$fixture/bin/$1"; chmod +x "$fixture/bin/$1"; }
mock busctl 'case $5 in LidClosed) f=lid ;; Docked) f=docked ;; esac
[[ $(<"$FIXTURE/$f") == 1 ]] && echo "b true" || echo "b false"'
mock systemctl 'echo "systemctl $*" >> "$FIXTURE/calls"
[[ $* != "--user is-active --quiet lid-awake.service" || -e $FIXTURE/active ]]'
mock omarchy-shell 'echo "omarchy-shell $*" >> "$FIXTURE/calls"; [[ $2 != isLocked ]] || cat "$FIXTURE/locked"'
mock omarchy-system-lock 'echo omarchy-system-lock >> "$FIXTURE/calls"'
mock omarchy-notification-send 'echo "notify $*" >> "$FIXTURE/calls"'

# set <lid> <docked> <ac> <capacity> <temp in tenths of °C> [locked]
set_state() {
    echo "$1" > "$fixture/lid"
    echo "$2" > "$fixture/docked"
    echo "$3" > "$fixture/ps/ac/online"
    echo "$4" > "$fixture/ps/bat/capacity"
    echo "$5" > "$fixture/ps/bat/temp"
    echo "${6:-true}" > "$fixture/locked"
    : > "$fixture/calls"
}
envs=(FIXTURE="$fixture" PATH="$fixture/bin:$PATH" LID_AWAKE_POWER_SUPPLY="$fixture/ps"
    LID_AWAKE_INTERVAL=0.1 LID_AWAKE_GRACE=0.1)
run() { env "${envs[@]}" bash "$script" "$@"; }
watch_briefly() { timeout 0.5 env "${envs[@]}" bash "$script" watch > "$fixture/log" || true; }
suspended() { grep -qx 'systemctl suspend' "$fixture/calls"; }
# `set -e` ignores a failing `! command`, so negative checks must exit explicitly.
not() { if "$@"; then printf 'FAIL: %s\n' "$*" >&2; exit 1; fi; }

set_state 0 0 0 10 300
watch_briefly
not suspended
printf 'PASS lid open never suspends, even at 10%%\n'

set_state 1 0 1 10 300
watch_briefly
not suspended
printf 'PASS closed on AC stays awake at 10%%\n'

set_state 1 0 0 21 300
watch_briefly
not suspended
set_state 1 0 0 20 300
watch_briefly
suspended
grep -q 'Suspending: battery at 20% on battery power' "$fixture/log"
printf 'PASS closed on battery suspends at 20%%, not 21%%\n'

set_state 1 0 1 90 449
watch_briefly
not suspended
set_state 1 0 1 90 450
watch_briefly
suspended
grep -q 'Suspending: battery at 45.0 °C' "$fixture/log"
printf 'PASS heat suspends at 45.0 °C even on AC, not 44.9 °C\n'

set_state 1 1 0 5 500
watch_briefly
not suspended
not grep -q omarchy-system-lock "$fixture/calls"
printf 'PASS docked clamshell is left alone\n'

set_state 1 0 1 90 300 false
watch_briefly
[[ $(grep -c omarchy-system-lock "$fixture/calls") == 1 ]]
set_state 1 0 1 90 300 true
watch_briefly
not grep -q omarchy-system-lock "$fixture/calls"
printf 'PASS an unlocked closed laptop is locked once; a locked one is not\n'

set_state 0 0 0 64 317
run status > "$fixture/out"
grep -qx 'Lid awake: off' "$fixture/out"
grep -qx 'Lid: open; battery 64%, 31.7 °C, on battery' "$fixture/out"
touch "$fixture/active"
set_state 1 1 1 64 317
run status > "$fixture/out"
grep -qx 'Lid awake: on' "$fixture/out"
grep -qx 'Lid: closed, docked; battery 64%, 31.7 °C, on AC' "$fixture/out"
printf 'PASS status (a USB supply online does not count as AC)\n'

set_state 0 0 0 64 317
run toggle
grep -qx 'systemctl --user stop lid-awake.service' "$fixture/calls"
grep -qx 'omarchy-shell jdpinto.lid-awake refresh' "$fixture/calls"
rm "$fixture/active"
set_state 0 0 0 64 317
run toggle
grep -qx 'systemctl --user start lid-awake.service' "$fixture/calls"
grep -q '^notify .*Lid awake on' "$fixture/calls"
not run bogus 2> /dev/null
printf 'PASS toggle, bar refresh, notification and usage error\n'
