#!/usr/bin/env python3
"""Regression tests using Kanata 1.12.0's offline input/output simulator.

This never opens an input device or injects real keyboard events. Build the
upstream kanata-sim package and pass its executable with --simulator.
"""
import argparse
import pathlib
import re
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
EVENT = re.compile(r"^out:([↓↑⟳])(.+)$", re.MULTILINE)


def tap(key):
    return [("↓", key), ("↑", key)]


def chord(modifier, key):
    return [("↓", modifier), *tap(key), ("↑", modifier)]


def simulate(binary, config, sequence, directory, name):
    source = directory / f"{name}.sim"
    source.write_text(sequence + " t:1200\n")
    result = subprocess.run(
        [str(binary), "--cfg", str(config), "--sim", str(source)],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )
    (directory / f"{name}.out").write_text(result.stdout)
    (directory / f"{name}.log").write_text(result.stderr)
    return EVENT.findall(result.stdout)


def assert_released(events, allow_repeat=False):
    pressed = set()
    for action, key in events:
        if action == "↓":
            assert allow_repeat or key not in pressed, f"duplicate press: {key}"
            pressed.add(key)
        elif action == "↑":
            assert key in pressed, f"release without press: {key}"
            pressed.remove(key)
        elif action == "⟳":
            assert key in pressed, f"repeat without press: {key}"
    assert not pressed, f"stuck keys: {pressed}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, type=pathlib.Path)
    parser.add_argument("--output-dir", type=pathlib.Path)
    args = parser.parse_args()
    config = ROOT / "spacefn.kbd"
    baseline = ROOT / "kanata.kbd"
    output = args.output_dir or pathlib.Path(tempfile.mkdtemp(prefix="kanata-spacefn-tests."))
    output.mkdir(parents=True, exist_ok=True)

    cases = [
        ("caps-short-tap", "d:caps t:40 u:caps", tap("Escape")),
        ("caps-long-hold", "d:caps t:240 u:caps", tap("LCtrl")),
        ("caps-control-a", "d:caps t:30 d:a t:30 u:a t:20 u:caps", chord("LCtrl", "A")),
        ("caps-tap-then-control", "d:caps t:30 u:caps t:30 d:caps t:20 d:a t:30 u:a t:20 u:caps", tap("Escape") + chord("LCtrl", "A")),
        ("space-short-tap", "d:spc t:40 u:spc", tap("Space")),
        ("space-two-taps", "d:spc t:30 u:spc t:40 d:spc t:30 u:spc", tap("Space") * 2),
        ("space-hold-without-navigation", "d:spc t:240 u:spc", []),
        ("leader-release-before-h", "d:spc t:40 u:spc t:20 d:h t:40 u:h", tap("Space") + tap("H")),
        ("all-navigation-directions", "d:spc t:240 d:h t:30 u:h t:20 d:j t:30 u:j t:20 d:k t:30 u:k t:20 d:l t:30 u:l t:20 u:spc", tap("Left") + tap("Down") + tap("Up") + tap("Right")),
        # The Linux simulator's InputEvent stores only an up/down Boolean,
        # so Repeat is displayed as another down. Native key_repeat.rs emits
        # KeyValue::Repeat; physical autorepeat still needs an application test.
        ("navigation-repeat", "d:spc t:240 d:h t:40 r:h t:40 r:h t:20 u:h t:20 u:spc", [("↓", "Left"), ("↓", "Left"), ("↓", "Left"), ("↑", "Left")]),
        ("release-space-before-arrow", "d:spc t:240 d:h t:30 u:spc t:30 u:h", tap("Left")),
        ("navigation-then-normal-h", "d:spc t:240 d:h t:30 u:h t:20 u:spc t:30 d:h t:30 u:h", tap("Left") + tap("H")),
        ("shift-before-space-selection", "d:lsft t:20 d:spc t:240 d:l t:30 u:l t:20 u:spc t:20 u:lsft", chord("LShift", "Right")),
        ("shift-after-space-selection", "d:spc t:240 d:lsft t:20 d:h t:30 u:h t:20 u:lsft t:20 u:spc", chord("LShift", "Left")),
        ("ctrl-before-space-word-motion", "d:lctl t:20 d:spc t:240 d:h t:30 u:h t:20 u:spc t:20 u:lctl", chord("LCtrl", "Left")),
        ("caps-before-space-word-motion", "d:caps t:20 d:spc t:240 d:h t:30 u:h t:20 u:spc t:20 u:caps", chord("LCtrl", "Left")),
        ("caps-after-space-word-motion", "d:spc t:240 d:caps t:20 d:l t:30 u:l t:20 u:caps t:20 u:spc", chord("LCtrl", "Right")),
        ("ctrl-space-prefix", "d:lctl t:20 d:spc t:50 u:spc t:20 u:lctl", chord("LCtrl", "Space")),
        ("caps-space-prefix", "d:caps t:20 d:spc t:50 u:spc t:20 u:caps", chord("LCtrl", "Space")),
        ("super-space-tap", "d:lmet t:20 d:spc t:50 u:spc t:20 u:lmet", chord("LGui", "Space")),
        ("super-space-long-hold", "d:lmet t:20 d:spc t:600 u:spc t:20 u:lmet", tap("LGui")),
        ("right-super-space-long-hold", "d:rmet t:20 d:spc t:600 u:spc t:20 u:rmet", tap("RGui")),
        ("alt-space-shortcut", "d:lalt t:20 d:spc t:50 u:spc t:20 u:lalt", chord("LAlt", "Space")),
        ("alt-spacefn-word-motion", "d:lalt t:20 d:spc t:240 d:h t:30 u:h t:20 u:spc t:20 u:lalt", chord("LAlt", "Left")),
        ("right-alt-unchanged", "d:ralt t:20 d:a t:30 u:a t:20 u:ralt", chord("RAlt", "A")),
        ("right-shift-normal-typing", "d:rsft t:20 d:l t:30 u:l t:20 u:rsft", chord("RShift", "L")),
    ]

    # Super+arrow navigation must work in either modifier order, without
    # emitting Space (which would prematurely open the Omarchy menu).
    for key, arrow in zip("hjkl", ("Left", "Down", "Up", "Right")):
        cases.append((
            f"super-first-navigation-{key}",
            f"d:lmet t:20 d:spc t:240 d:{key} t:30 u:{key} t:20 u:spc t:20 u:lmet",
            chord("LGui", arrow),
        ))
        cases.append((
            f"space-first-super-navigation-{key}",
            f"d:spc t:240 d:lmet t:20 d:{key} t:30 u:{key} t:20 u:lmet t:20 u:spc",
            chord("LGui", arrow),
        ))
    cases.append((
        "super-shift-navigation",
        "d:lmet t:20 d:lsft t:20 d:spc t:240 d:l t:30 u:l t:20 u:spc t:20 u:lsft t:20 u:lmet",
        [("↓", "LGui"), ("↓", "LShift"), *tap("Right"), ("↑", "LShift"), ("↑", "LGui")],
    ))

    # The remaining mappings from the active Mac SpaceFN profile. Media
    # output is simulated only: these tests cannot change actual playback.
    extra = {
        "m": ("M", "PgDown"),
        "comm": ("Comma", "PgUp"),
        "n": ("N", "Home"),
        "Period": ("Dot", "End"),
        "Slash": ("Slash", "Grave"),
        "bspc": ("BSpace", "Delete"),
        "b": ("B", "Space"),
        "1": ("Kb1", "BrightnessDown"),
        "2": ("Kb2", "BrightnessUp"),
        "7": ("Kb7", "MediaPreviousSong"),
        "8": ("Kb8", "MediaPlayPause"),
        "9": ("Kb9", "MediaNextSong"),
        "0": ("Kb0", "Mute"),
        "min": ("Minus", "VolDown"),
        "eql": ("Equal", "VolUp"),
    }
    for key, (literal, action) in extra.items():
        cases.append((
            f"added-navigation-{key}",
            f"d:spc t:240 d:{key} t:30 u:{key} t:20 u:spc",
            tap(action),
        ))
        cases.append((f"added-base-{key}", f"d:{key} t:30 u:{key}", tap(literal)))
        cases.append((
            f"added-layer-release-{key}",
            f"d:spc t:240 d:{key} t:30 u:{key} t:20 u:spc t:30 d:{key} t:30 u:{key}",
            tap(action) + tap(literal),
        ))
        if key not in ("7", "8", "9", "0"):
            cases.append((
                f"added-{key}-repeat",
                f"d:spc t:240 d:{key} t:30 r:{key} t:30 r:{key} t:20 u:{key} t:20 u:spc",
                [("↓", action)] * 3 + [("↑", action)],
            ))
    # Former Home/End positions must stay literal, even while Nav is held.
    for key, literal in (("g", "G"), ("scln", "SColon")):
        cases.append((f"former-home-end-base-{key}", f"d:{key} t:30 u:{key}", tap(literal)))
        cases.append((
            f"former-home-end-nav-{key}",
            f"d:spc t:240 d:{key} t:30 u:{key} t:20 u:spc",
            tap(literal),
        ))
    cases.extend([
        ("shift-slash-tilde", "d:lsft t:20 d:spc t:240 d:Slash t:30 u:Slash t:20 u:spc t:20 u:lsft", chord("LShift", "Grave")),
        ("ctrl-home", "d:caps t:20 d:spc t:240 d:n t:30 u:n t:20 u:spc t:20 u:caps", chord("LCtrl", "Home")),
        ("ctrl-end", "d:caps t:20 d:spc t:240 d:Period t:30 u:Period t:20 u:spc t:20 u:caps", chord("LCtrl", "End")),
        ("shift-home", "d:lsft t:20 d:spc t:240 d:n t:30 u:n t:20 u:spc t:20 u:lsft", chord("LShift", "Home")),
        ("shift-end", "d:lsft t:20 d:spc t:240 d:Period t:30 u:Period t:20 u:spc t:20 u:lsft", chord("LShift", "End")),
        ("ctrl-shift-home", "d:caps t:20 d:lsft t:20 d:spc t:240 d:n t:30 u:n t:20 u:spc t:20 u:lsft t:20 u:caps", [("↓", "LCtrl"), ("↓", "LShift"), *tap("Home"), ("↑", "LShift"), ("↑", "LCtrl")]),
        ("ctrl-shift-end", "d:caps t:20 d:lsft t:20 d:spc t:240 d:Period t:30 u:Period t:20 u:spc t:20 u:lsft t:20 u:caps", [("↓", "LCtrl"), ("↓", "LShift"), *tap("End"), ("↑", "LShift"), ("↑", "LCtrl")]),
        ("space-b-then-navigation", "d:spc t:240 d:b t:30 u:b t:20 d:h t:30 u:h t:20 u:spc", tap("Space") + tap("Left")),
        ("ctrl-space-b-prefix", "d:caps t:20 d:spc t:240 d:b t:30 u:b t:20 u:spc t:20 u:caps", chord("LCtrl", "Space")),
    ])

    # Fast overlapping Space + key must remain normal typing, including all
    # newly mapped letters, punctuation, digits, and Backspace.
    literals = {key: key.upper() for key in "hjklna"}
    literals.update({key: literal for key, (literal, _) in extra.items()})
    literals.update({"g": "G", "scln": "SColon"})
    for key, literal in literals.items():
        for delay in (15, 40, 70):
            cases.append((
                f"typing-roll-{key}-{delay}",
                f"d:spc t:{delay} d:{key} t:15 u:spc t:20 u:{key}",
                tap("Space") + tap(literal),
            ))
            cases.append((
                f"typing-nested-{key}-{delay}",
                f"d:spc t:{delay} d:{key} t:15 u:{key} t:20 u:spc",
                tap("Space") + tap(literal),
            ))

    # Space cannot be emitted prematurely: it must remain pending until its
    # release or hold decision, even with Super already down. The final drain
    # activates navigation. This intentionally leaves Super/Space down.
    events = simulate(args.simulator, config, "d:lmet t:20 d:spc t:20", output, "super-space-not-premature")
    assert events == [("↓", "LGui")], events
    print("PASS super-space-not-premature")

    passed = 1
    for name, sequence, expected in cases:
        events = simulate(args.simulator, config, sequence, output, name)
        if name.startswith(("typing-roll-", "typing-nested-")):
            # Buffered rolls can replay overlapping releases in either order.
            # What matters for text is ordered Space + letter presses, no
            # arrows/modifiers, and balanced releases for every emitted key.
            presses = [key for action, key in events if action == "↓"]
            expected_presses = [key for action, key in expected if action == "↓"]
            assert presses == expected_presses, f"{name}: expected {expected_presses}, got {events}"
        else:
            assert events == expected, f"{name}: expected {expected}, got {events}"
        assert_released(events, allow_repeat=name.endswith("-repeat"))
        print(f"PASS {name}")
        passed += 1

    # Compare the accepted Caps policy directly against the saved Caps-only
    # config, including Control+H/J/K/L without Space (e.g. editor splits).
    baseline_sequences = [case[:2] for case in cases[:4]]
    baseline_sequences += [
        (f"caps-control-{key}", f"d:caps t:20 d:{key} t:30 u:{key} t:20 u:caps")
        for key in "hjkl"
    ]
    baseline_sequences += [
        (f"ordinary-{key}", f"d:{key} t:30 u:{key}")
        for key in extra
    ]
    for name, sequence in baseline_sequences:
        old = simulate(args.simulator, baseline, sequence, output, f"baseline-{name}")
        new = simulate(args.simulator, config, sequence, output, f"compare-{name}")
        assert new == old, f"Caps behavior changed in {name}: {old} -> {new}"
        assert_released(new)
        print(f"PASS unchanged-{name}")
        passed += 1

    print(f"\n{passed} simulation checks passed; artifacts: {output}")


if __name__ == "__main__":
    main()
