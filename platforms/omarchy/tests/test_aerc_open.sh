#!/usr/bin/env bash
# Isolated tests: aerc, its socket, Hyprland, uwsm and notifications are all
# mocked. The only real process signalled is a `sleep` started here.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$root/home/.local/bin/aerc-open"
fixture=$(mktemp -d)
spawned=()
cleanup() {
    local pid
    for pid in "${spawned[@]}"; do kill "$pid" 2>/dev/null || true; done
    rm -r -- "$fixture"
}
trap cleanup EXIT
mkdir -p "$fixture/bin"

mock() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$fixture/bin/$1"; chmod +x "$fixture/bin/$1"; }
log='printf "%s\n" "$(basename "$0") $*" >> "$FIXTURE/calls"'
mock pgrep 'cat "$FIXTURE/pgrep" 2>/dev/null || exit 1'
mock readlink 'pid=${1#/proc/}; cat "$FIXTURE/tty-${pid%%/*}"'
mock ss 'cat "$FIXTURE/ss" 2>/dev/null || true'
mock ps 'cat "$FIXTURE/ppid-$4" 2>/dev/null || exit 1'
mock hyprctl "$log"'
[[ $1 != clients ]] || cat "$FIXTURE/clients.json"'
# Like the real one without a terminal, the mock logs to stdout before any
# "response: <error>" line.
mock aerc "$log"'
echo "DEBUG 2026/01/01 00:00:00.000000 general.go:87: aerc.conf: [general] ..."
cat "$FIXTURE/aerc-output" 2>/dev/null || true
exit "$(cat "$FIXTURE/aerc-exit" 2>/dev/null || echo 0)"'
mock uwsm-app "$log"
mock omarchy-notification-send "$log"

# reset [owner pid]: no aerc at all, or one serving the socket.
reset() {
    rm -f -- "$fixture"/{calls,pgrep,ss,aerc-output,aerc-exit,clients.json,tty-*,ppid-*}
    : > "$fixture/calls"
    echo '[]' > "$fixture/clients.json"
    if [[ -n ${1:-} ]]; then
        printf 'u_str LISTEN 0 4096 /run/user/1000/aerc.sock 1 * 0 users:(("aerc",pid=%s,fd=9))\n' \
            "$1" > "$fixture/ss"
    fi
}
run() { env FIXTURE="$fixture" PATH="$fixture/bin:$PATH" bash "$script" "$@"; }
called() { grep -qxF -- "$1" "$fixture/calls"; }
# `set -e` ignores a failing `! command`, so negative checks must exit explicitly.
not() { if "$@"; then printf 'FAIL: %s\n' "$*" >&2; exit 1; fi; }
launch='uwsm-app -t service -- xdg-terminal-exec --app-id=org.omarchy.aerc -e aerc'

reset
run
called "$launch"
printf 'PASS no aerc running: starts one in a terminal\n'

reset
run 'mailto:%22Jane%20Doe%22%20%3Cjane@example.org%3E?subject=Hi%20there&body=a%26b'
called "$launch mailto:\"Jane Doe\" <jane@example.org>?subject=Hi%20there&body=a%26b"
printf 'PASS starts aerc with the link, address decoded, query left to aerc\n'

reset
run 'mailto:jane@example.org,%zz@example.org'
called "$launch mailto:jane@example.org,%zz@example.org"
printf 'PASS leaves plain addresses and stray %% signs alone\n'

reset 111
echo 222 > "$fixture/ppid-111"
echo '[{"pid": 999, "address": "0xother"}, {"pid": 222, "address": "0xkitty"}]' \
    > "$fixture/clients.json"
run 'mailto:jane%40example.org'
called 'aerc mailto:jane@example.org'
called "hyprctl dispatch hl.dsp.focus({ window = 'address:0xkitty' })"
not called "$launch mailto:jane@example.org"
printf 'PASS running aerc gets the link and its terminal window is focused\n'

reset 111
echo '[{"pid": 222, "address": "0xkitty"}]' > "$fixture/clients.json"
echo 222 > "$fixture/ppid-111"
run
not grep -q '^aerc ' "$fixture/calls"
called "hyprctl dispatch hl.dsp.focus({ window = 'address:0xkitty' })"
printf 'PASS no link: just focuses the running aerc\n'

reset 111
echo 1 > "$fixture/ppid-111"
run mailto:
called 'aerc mailto:'
grep -q '^omarchy-notification-send aerc has no window to focus' "$fixture/calls"
not grep -q '^hyprctl dispatch' "$fixture/calls"
printf 'PASS aerc without a window (tmux, Herdr) still gets the link, with a notice\n'

reset 111
echo 'response: Could not parse to: mail: no angle-addr' > "$fixture/aerc-output"
if run 'mailto:bad'; then printf 'FAIL rejected link exited 0\n' >&2; exit 1; fi
grep -q '^omarchy-notification-send aerc could not open the link Could not parse' \
    "$fixture/calls"
not grep -q '^hyprctl dispatch' "$fixture/calls"
printf 'PASS a link aerc rejects is reported, not silently dropped\n'

reset 111
echo 'panic: open /dev/tty: no such device or address' > "$fixture/aerc-output"
echo 2 > "$fixture/aerc-exit"
if run 'mailto:jane@example.org'; then printf 'FAIL failed hand-off exited 0\n' >&2; exit 1; fi
grep -q '^omarchy-notification-send aerc could not open the link panic: open /dev/tty' \
    "$fixture/calls"
printf 'PASS a failed hand-off is reported with aerc'"'"'s last line\n'

# Detached, so they are reparented and reaped at once instead of lingering as
# zombies of this shell (which `kill -0` would still find).
detached_sleep() { (sleep 60 >/dev/null 2>&1 & echo $!); }
orphan=$(detached_sleep)
live=$(detached_sleep)
spawned+=("$orphan" "$live")
reset
printf '%s\n%s\n' "$orphan" "$live" > "$fixture/pgrep"
echo '/dev/pts/9 (deleted)' > "$fixture/tty-$orphan"
echo '/dev/pts/3' > "$fixture/tty-$live"
run 'mailto:jane@example.org'
not kill -0 "$orphan" 2>/dev/null
kill -0 "$live"
called "$launch mailto:jane@example.org"
printf 'PASS ends an aerc whose terminal is gone, keeps one that has a terminal\n'

reset
if run 'https://example.org' 2>/dev/null; then printf 'FAIL non-mailto exited 0\n' >&2; exit 1; fi
not grep -q . "$fixture/calls"
printf 'PASS refuses anything but a mailto: link\n'
