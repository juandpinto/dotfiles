# %%
"""Validate Mac terminal configuration with Kitty's bundled parser, without a GUI."""

from __future__ import annotations

import importlib
import importlib.util
import shlex
import unittest
from pathlib import Path
from typing import Any

import tomllib

ROOT = Path(__file__).resolve().parents[1]
KITTY = ROOT / ".config/kitty"


@unittest.skipUnless(
    importlib.util.find_spec("kitty"), "Requires Kitty's embedded Python"
)
class MacTerminalTests(unittest.TestCase):
    """Check parser compatibility and the Mac/Linux deployment boundaries."""

    def parse_kitty(self, *paths: Path) -> Any:
        """Parse authored files with the installed Kitty's own option types."""
        bad_lines: list[Any] = []
        config = importlib.import_module("kitty.config")
        options = config.load_config(
            *(str(path) for path in paths), accumulate_bad_lines=bad_lines
        )
        self.assertEqual(bad_lines, [])
        return options

    def test_mac_options_and_herdr_startup(self) -> None:
        """Preserve the Mac display settings and initialize zsh before Herdr."""
        options = self.parse_kitty(KITTY / "kitty.conf")
        self.assertEqual(str(options.font_family), "MesloLGS Nerd Font Mono")
        self.assertEqual(options.font_size, 14.0)
        self.assertEqual(options.background_opacity, 0.93)
        self.assertEqual(options.background_blur, 10)
        self.assertEqual(options.allow_remote_control, "socket-only")
        self.assertTrue(options.listen_on.startswith("unix:"))
        self.assertTrue(options.macos_option_as_alt)
        self.assertEqual(
            shlex.split(options.shell), ["/bin/zsh", "-lic", "exec herdr"]
        )
        self.assertEqual(options.tab_bar_style, "hidden")
        for name in ["HERDR_ENV", "HERDR_SOCKET_PATH", "TMUX", "WEZTERM_PANE"]:
            self.assertIn(name, options.env)
            self.assertNotEqual(options.env[name], "")

    def test_native_auto_palettes_match_linux(self) -> None:
        """Keep both ANSI palettes aligned without importing Linux settings."""
        for mode, linux_name in [
            ("dark", "everforest"),
            ("light", "everforest-light"),
        ]:
            with self.subTest(mode=mode):
                palette_file = (
                    ROOT
                    / "platforms/omarchy/home/.config/omarchy/themes"
                    / linux_name
                    / "colors.toml"
                )
                palette = tomllib.loads(
                    palette_file.read_text(encoding="utf-8")
                )
                options = self.parse_kitty(
                    KITTY / "kitty.conf", KITTY / f"{mode}-theme.auto.conf"
                )
                self.assertEqual(
                    options.background.as_sharp, palette["background"]
                )
                self.assertEqual(
                    options.foreground.as_sharp, palette["foreground"]
                )
                for index, color in enumerate(
                    ["red", "green", "yellow", "blue", "magenta", "cyan"], 1
                ):
                    self.assertEqual(
                        getattr(options, f"color{index}").as_sharp,
                        palette[color],
                    )
                    self.assertEqual(
                        getattr(options, f"color{index + 8}").as_sharp,
                        palette[color],
                    )
        self.assertEqual(
            (KITTY / "no-preference-theme.auto.conf").resolve(),
            (KITTY / "light-theme.auto.conf").resolve(),
        )

    def test_shared_herdr_preserves_existing_linux_links(self) -> None:
        """The compatibility pointer must resolve to the canonical shared file."""
        shared = ROOT / ".config/herdr/config.toml"
        legacy = ROOT / "platforms/omarchy/home/.config/herdr/config.toml"
        self.assertTrue(legacy.is_symlink())
        self.assertEqual(shared.resolve(), legacy.resolve())
        config = tomllib.loads(shared.read_text(encoding="utf-8"))
        self.assertEqual(config["keys"]["prefix"], "ctrl+b")
        self.assertEqual(config["keys"]["detach"], "prefix+d")
        self.assertTrue(config["theme"]["auto_switch"])
        linker = (ROOT / "platforms/omarchy/link.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn(".config/herdr/config.toml", linker)

    def test_mac_launcher_and_no_managed_hook_in_repo(self) -> None:
        """Launch Kitty from AeroSpace and keep Herdr's generated hook local."""
        path = ROOT / ".config/aerospace/aerospace.toml"
        aerospace = tomllib.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(
            aerospace["mode"]["main"]["binding"]["alt-cmd-ctrl-t"],
            "exec-and-forget open -a kitty",
        )
        self.assertFalse(
            (ROOT / ".config/pi/agent/extensions/herdr-agent-state.ts").exists()
        )


if __name__ == "__main__":
    unittest.main()
