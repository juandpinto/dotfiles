#!/usr/bin/env python3
"""Read-only verification: SpaceFN media keycodes -> XKB -> existing bindings.

Does not emit events or change volume/brightness/media playback. Uses the
current internal keyboard's layout/options and libxkbcommon's stable C API.
"""
import ctypes
import ctypes.util
import json
import subprocess


MEDIA = [
    ("Space+1", 224, "XF86MonBrightnessDown"),
    ("Space+2", 225, "XF86MonBrightnessUp"),
    ("Space+7", 165, "XF86AudioPrev"),
    ("Space+8", 164, "XF86AudioPlay"),
    ("Space+9", 163, "XF86AudioNext"),
    ("Space+0", 113, "XF86AudioMute"),
    ("Space+-", 114, "XF86AudioLowerVolume"),
    ("Space+=", 115, "XF86AudioRaiseVolume"),
]


class RuleNames(ctypes.Structure):
    _fields_ = [(name, ctypes.c_char_p) for name in
                ("rules", "model", "layout", "variant", "options")]


def main():
    devices = json.loads(subprocess.check_output(["/usr/bin/hyprctl", "-j", "devices"]))
    keyboard = next(k for k in devices["keyboards"] if k["name"] == "apple-spi-keyboard")
    bindings = json.loads(subprocess.check_output(["/usr/bin/hyprctl", "-j", "binds"]))
    library = ctypes.util.find_library("xkbcommon")
    assert library, "libxkbcommon is unavailable"
    xkb = ctypes.CDLL(library)
    pointer = ctypes.c_void_p
    uint = ctypes.c_uint32
    syms_pointer = ctypes.POINTER(uint)
    xkb.xkb_context_new.argtypes = [ctypes.c_int]
    xkb.xkb_context_new.restype = pointer
    xkb.xkb_context_unref.argtypes = [pointer]
    xkb.xkb_context_unref.restype = None
    xkb.xkb_keymap_new_from_names.argtypes = [pointer, ctypes.POINTER(RuleNames), ctypes.c_int]
    xkb.xkb_keymap_new_from_names.restype = pointer
    xkb.xkb_keymap_unref.argtypes = [pointer]
    xkb.xkb_keymap_unref.restype = None
    xkb.xkb_keymap_key_get_syms_by_level.argtypes = [pointer, uint, uint, uint, ctypes.POINTER(syms_pointer)]
    xkb.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
    xkb.xkb_keysym_get_name.argtypes = [uint, ctypes.POINTER(ctypes.c_char), ctypes.c_size_t]
    xkb.xkb_keysym_get_name.restype = ctypes.c_int

    values = [(keyboard.get(name) or None) for name in
              ("rules", "model", "layout", "variant", "options")]
    names = RuleNames(*(value.encode() if value else None for value in values))
    context = xkb.xkb_context_new(0)
    assert context, "could not create XKB context"
    keymap = None
    try:
        keymap = xkb.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
        assert keymap, "could not compile the current keyboard layout"
        for chord, code, expected in MEDIA:
            syms = syms_pointer()
            count = xkb.xkb_keymap_key_get_syms_by_level(
                keymap, code + 8, keyboard.get("active_layout_index", 0), 0, ctypes.byref(syms)
            )
            assert count > 0, f"no keysym for {chord}"
            actual = []
            for index in range(count):
                buffer = ctypes.create_string_buffer(128)
                assert xkb.xkb_keysym_get_name(syms[index], buffer, len(buffer)) > 0
                actual.append(buffer.value.decode())
            assert expected in actual, f"{chord}: expected {expected}, got {actual}"
            matching = [b for b in bindings if b.get("key") == expected and b.get("modmask") == 0]
            assert matching, f"no existing unmodified desktop binding for {expected}"
            print(f"PASS {chord}: {expected} -> {matching[0].get('description', 'existing binding')}")
        print("\n8 media/brightness routes verified without executing their actions.")
    finally:
        if keymap:
            xkb.xkb_keymap_unref(keymap)
        xkb.xkb_context_unref(context)


if __name__ == "__main__":
    main()
