#!/usr/bin/env bash
# Screensaver checks. Isolated: the animation runs in a private tmux server in
# --preview mode, so the desktop, focus and real screensaver windows are never
# touched. The run waits for two random Omarchy effects, so allow a minute.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
saver="$root/home/.config/kitty/exe-overrides/omarchy-screensaver"

bash -n "$saver"
[[ -x $saver ]]
# Kitty must look in a directory holding nothing but this override.
grep -qx 'exe_search_path ~/.config/kitty/exe-overrides' "$root/home/.config/kitty/kitty.conf"
[[ $(ls -A "$(dirname -- "$saver")") == omarchy-screensaver ]]
printf 'PASS kitty finds only our omarchy-screensaver ahead of PATH\n'

# The screensaver's renderer, as plain text: render <cols> <rows> <progress>.
render() {
    bash -c 'eval "$(sed -n "/^THEME=/,/^RAINBOW+=/p" "$1")"; eval "$(sed -n "/^render()/,/^}/p" "$1")"; render text "$2" "$3" "$4"' \
        - "$saver" "$@" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/⠀//' -e 's/ *$//'
}
# The letters are the bar monogram's geometry: same lean, same strokes for the
# hook, the foot and the d's tip as the module's paths, all seven letters.
module="$root/home/.config/omarchy/bar/modules/jdp-menu.qml"
grep -q 'LEAN = 0.21256' "$saver" && grep -q 'Math.tan(12 \* Math.PI / 180)' "$module"
grep -q 'G\[1\] = "10 19 0 0 9 9;22 67 0 0 9 9;67 76 0 -9 9 0;67 76 -8 -10 0 -9"' "$saver" # j: 9-unit dot and stem, 45-degree hook, cut foot
grep -q 'M23 67 H32 L23 76 H13 L15 67 Z' "$module"                                        # the same hook and foot in the module
grep -q 'G\[2\] = "4 13 36 27 36 36;' "$saver" && grep -q 'M50 13 L59 4 V22 H50 Z' "$module" # d tip cut at 45 degrees
for k in 1 2 3 4 5 6 7; do grep -q "G\\[$k\\] = " "$saver"; done
[[ $(render 140 30 0 | grep -c .) -ge 12 ]] # the monogram, about 18 rows at this size
printf 'PASS the screensaver letters are the bar monogram'"'"'s geometry\n'
[[ $(render 140 30 1 | grep -c .) -ge 12 ]] # the word, the same height
printf 'PASS the word renders\n'

cols=88 rows=25 # the screensaver terminal: kitty at font_size 18 on this display
T=(tmux -L omarchy-screensaver-test -f /dev/null)
"${T[@]}" kill-server 2>/dev/null || true
trap '"${T[@]}" kill-server 2>/dev/null || true' EXIT
screen() { "${T[@]}" capture-pane -p -t s | sed -e 's/⠀//' -e 's/ *$//'; }
wait_for_screen() { # label expected timeout
    local deadline=$((SECONDS + $3))
    while ((SECONDS < deadline)); do
        [[ $(screen) == "$2" ]] && { printf 'PASS %s\n' "$1"; return 0; }
        sleep 0.1
    done
    printf 'FAIL %s\n' "$1"; screen | sed '/^$/d'; exit 1
}
wait_for_change() { # label from timeout
    local deadline=$((SECONDS + $3))
    while ((SECONDS < deadline)); do [[ $(screen) != "$2" ]] && return 0; sleep 0.05; done
    printf 'FAIL %s never started\n' "$1"; exit 1
}

monogram=$(render "$cols" "$rows" 0) word=$(render "$cols" "$rows" 1)
"${T[@]}" new-session -d -s s -x "$cols" -y "$rows" "$saver --preview"
wait_for_screen "an Omarchy effect builds the monogram exactly on our frame" "$monogram" 45
wait_for_screen "the monogram splits and unfolds into the word" "$word" 10
sleep 4.6 # word hold (2.5 s) and rainbow (1.2 s), into the rainbow hold
colors=$("${T[@]}" capture-pane -p -e -t s | grep -o '38;2;[0-9;]*' | sort -u | wc -l)
[[ $colors -eq 7 ]] || { printf 'FAIL rainbow shows %s colours, not 7\n' "$colors"; exit 1; }
printf 'PASS the rainbow gives each letter its workspace colour\n'
wait_for_change "the second effect" "$word" 15
wait_for_screen "an Omarchy effect rebuilds the word exactly on our frame" "$word" 45
wait_for_screen "the word folds back into the monogram" "$monogram" 15
"${T[@]}" send-keys -t s x
sleep 0.5
! "${T[@]}" has-session -t s 2>/dev/null || { printf 'FAIL a key should end it\n'; exit 1; }
printf 'PASS a key ends it\n'
