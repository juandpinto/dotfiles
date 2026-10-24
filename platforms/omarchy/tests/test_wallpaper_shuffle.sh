#!/usr/bin/env bash
# Isolated tests: the real desktop, images, and Omarchy IPC are never touched.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$root/home/.local/bin/wallpaper-shuffle"
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
home="$fixture/home"
images="$home/Documents/backgrounds"
state="$home/.local/state/omarchy/current"
mkdir -p "$images" "$state" "$fixture/bin"
cat > "$fixture/bin/omarchy" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 4 && $1 == theme && $2 == bg && $3 == set && -f $4 ]]
[[ ! -e $HOME/fail ]] || exit 42
printf '%s\0' "$4" >> "$HOME/calls"
ln -sfn -- "$4" "$HOME/.local/state/omarchy/current/background"
MOCK
chmod +x "$fixture/bin/omarchy"
run() { HOME="$home" PATH="$fixture/bin:$PATH" bash "$script" "$@"; }
current() { readlink -f -- "$state/background"; }

run "$fixture/missing"
run
[[ ! -e $state/background ]]
printf 'PASS missing and empty folders\n'

touch "$images/notes.txt"
run
[[ ! -e $state/background ]]
printf 'PASS unsupported files ignored\n'

first="$images/a spaced.PNG"
touch "$first"
run
[[ $(current) == "$first" ]]
before=$(stat -c %s "$home/calls")
run
[[ $(current) == "$first" && $(stat -c %s "$home/calls") == "$before" ]]
printf 'PASS uppercase extension, spaces, and single-image no-op\n'

second="$images/"$'b\nline.jpeg'
touch "$second"
mkdir "$images/nested"
touch "$images/nested/ignored.png"
previous=$first
for _ in {1..12}; do
    run
    next=$(current)
    [[ $next == "$first" || $next == "$second" ]]
    [[ $next != "$previous" ]]
    previous=$next
done
printf 'PASS shuffled selection, no immediate repeats, newline names, no recursion\n'

touch "$home/fail"
if run; then
    printf 'FAIL Omarchy errors must propagate\n' >&2
    exit 1
else
    [[ $? == 42 ]]
fi
[[ $(current) == "$previous" ]]
printf 'PASS failed background update preserves current selection\n'
printf 'All wallpaper shuffle checks passed.\n'
