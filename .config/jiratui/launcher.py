# %%
"""Launch JiraTUI with the local Everforest themes."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from textual.theme import BUILTIN_THEMES, Theme

APPEARANCE_FILE = Path.home() / ".cache" / "appearance"
SECRETS_FILE = Path.home() / ".config" / "jiratui" / "secrets.env"

# These are the official Everforest medium-contrast palettes used by the other dotfiles themes in this repository.
EVERFOREST_DARK = Theme(
    name="everforest-dark",
    primary="#83c092",
    secondary="#7fbbb3",
    warning="#dbbc7f",
    error="#e67e80",
    success="#a7c080",
    accent="#d699b6",
    foreground="#d3c6aa",
    background="#2d353b",
    surface="#343f44",
    panel="#3d484d",
    variables={
        "foreground-muted": "#859289",
        "border-blurred": "#4f585e",
        "block-cursor-foreground": "#2d353b",
        "block-cursor-background": "#83c092",
        "block-cursor-text-style": "none",
        "input-selection-background": "#83c092 35%",
        "button-color-foreground": "#2d353b",
        "footer-key-foreground": "#83c092",
    },
)

EVERFOREST_LIGHT = Theme(
    name="everforest-light",
    primary="#35a77c",
    secondary="#3a94c5",
    warning="#dfa000",
    error="#f85552",
    success="#8da101",
    accent="#df69ba",
    foreground="#5c6a72",
    background="#fdf6e3",
    surface="#f4f0d9",
    panel="#efebd4",
    dark=False,
    variables={
        "foreground-muted": "#939f91",
        "border-blurred": "#bdc3af",
        "block-cursor-foreground": "#fdf6e3",
        "block-cursor-background": "#35a77c",
        "block-cursor-text-style": "none",
        "input-selection-background": "#35a77c 30%",
        "button-color-foreground": "#fdf6e3",
        "footer-key-foreground": "#35a77c",
    },
)

EVERFOREST_THEMES = {
    EVERFOREST_DARK.name: EVERFOREST_DARK,
    EVERFOREST_LIGHT.name: EVERFOREST_LIGHT,
}


def register_themes() -> None:
    """Make the local themes available to JiraTUI and its CLI validation."""

    BUILTIN_THEMES.update(EVERFOREST_THEMES)


def load_credentials() -> None:
    """Load local Jira credentials without adding them to the tracked config."""

    load_dotenv(SECRETS_FILE, override=False)


def appearance_theme() -> str:
    """Return the Everforest theme matching the shared appearance state."""

    try:
        appearance = APPEARANCE_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        appearance = "dark"
    return "everforest-light" if appearance == "light" else "everforest-dark"


def main() -> None:
    """Run JiraTUI with Everforest registration and live appearance syncing."""

    load_credentials()
    register_themes()

    import jiratui.cli as jiratui_cli
    from jiratui.app import JiraApp

    class EverforestJiraApp(JiraApp):
        """JiraTUI app that follows the shared appearance state."""

        def __init__(self, settings: Any, *args: Any, **kwargs: Any) -> None:
            user_theme = kwargs.get("user_theme")
            self._follow_appearance = user_theme is None and settings.theme in {
                None,
                "everforest-dark",
                "everforest-light",
            }
            if self._follow_appearance:
                settings.theme = appearance_theme()
            super().__init__(settings, *args, **kwargs)

        async def on_mount(self) -> None:
            # Textual dispatches inherited mount handlers itself; calling super would mount JiraTUI's main screen twice.
            if self._follow_appearance:
                self.set_interval(2.0, self._sync_appearance)

        def _sync_appearance(self) -> None:
            if self._follow_appearance:
                theme = appearance_theme()
                if self.theme != theme:
                    self.theme = theme

    # JiraTUI constructs its app through this module-level reference. Replace it without modifying the upstream installation; the headless tests cover this integration boundary.
    jiratui_cli.JiraApp = EverforestJiraApp  # ty: ignore[invalid-assignment]
    jiratui_cli.jiratuicli()


if __name__ == "__main__":
    sys.exit(main())
