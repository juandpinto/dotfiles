# %%
"""Test the JiraTUI wrapper without credentials, Jira requests, or a real TTY."""

from __future__ import annotations

import os
import runpy
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest import mock

import jiratui.app
import jiratui.cli
from textual.app import App
from textual.theme import BUILTIN_THEMES

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / ".config/jiratui/launcher.py"


class LocalJiraApp(App[None]):
    """Exercise real Textual event dispatch without initializing Jira clients."""

    def __init__(self, settings: Any, **kwargs: Any) -> None:
        super().__init__()
        self.theme = kwargs.get("user_theme") or settings.theme
        self.mount_count = 0

    def on_mount(self) -> None:
        """Count inherited mount dispatches to detect duplicate initialization."""
        self.mount_count += 1


# %%
class JiraLauncherTests(unittest.IsolatedAsyncioTestCase):
    """Cover theme routing, credentials isolation, and inherited mount behavior."""

    def setUp(self) -> None:
        """Load fresh wrapper globals and isolate every filesystem write."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        loaded = runpy.run_path(str(LAUNCHER))
        self.launcher = loaded["main"].__globals__
        self.appearance = self.root / "appearance"
        self.secrets = self.root / "secrets.env"
        self.launcher["APPEARANCE_FILE"] = self.appearance
        self.launcher["SECRETS_FILE"] = self.secrets
        self.enterContext(mock.patch.dict(BUILTIN_THEMES))

    def app_class(self) -> Any:
        """Capture the replacement class without invoking the real Jira CLI."""
        classes = []
        with (
            mock.patch.object(jiratui.app, "JiraApp", LocalJiraApp),
            mock.patch.object(jiratui.cli, "JiraApp"),
            mock.patch.object(
                jiratui.cli,
                "jiratuicli",
                side_effect=lambda: classes.append(jiratui.cli.JiraApp),
            ),
        ):
            self.launcher["main"]()
        return classes[0]

    def test_missing_or_unknown_appearance_defaults_to_dark(self) -> None:
        """Missing and unrecognized state must have a deterministic fallback."""
        self.assertEqual(self.launcher["appearance_theme"](), "everforest-dark")
        self.appearance.write_text("unknown\n", encoding="utf-8")
        self.assertEqual(self.launcher["appearance_theme"](), "everforest-dark")

    def test_light_appearance_is_trimmed(self) -> None:
        """Accept the newline written by both platform appearance publishers."""
        self.appearance.write_text("light\n", encoding="utf-8")
        self.assertEqual(
            self.launcher["appearance_theme"](), "everforest-light"
        )

    def test_credentials_do_not_override_environment(self) -> None:
        """Load only the fixture and preserve an explicitly exported value."""
        name = "DOTFILES_JIRATUI_TEST_CREDENTIAL"
        self.secrets.write_text(f"{name}=fixture\n", encoding="utf-8")
        with mock.patch.dict(os.environ, {name: "exported"}):
            self.launcher["load_credentials"]()
            self.assertEqual(os.environ[name], "exported")

    def test_both_themes_are_registered(self) -> None:
        """Textual must resolve both custom names before the Jira CLI loads."""
        self.launcher["register_themes"]()
        self.assertTrue(BUILTIN_THEMES["everforest-dark"].dark)
        self.assertFalse(BUILTIN_THEMES["everforest-light"].dark)

    async def test_follow_appearance_and_mount_parent_once(self) -> None:
        """Use real headless dispatch, then switch the shared appearance file."""
        self.appearance.write_text("light\n", encoding="utf-8")
        app = self.app_class()(SimpleNamespace(theme="everforest-dark"))
        self.assertEqual(app.theme, "everforest-light")
        async with app.run_test():
            self.assertEqual(app.mount_count, 1)
            self.appearance.write_text("dark\n", encoding="utf-8")
            app._sync_appearance()
            self.assertEqual(app.theme, "everforest-dark")

    async def test_explicit_cli_theme_disables_following(self) -> None:
        """A CLI theme remains authoritative when the shared state changes."""
        self.appearance.write_text("light\n", encoding="utf-8")
        app = self.app_class()(
            SimpleNamespace(theme="everforest-dark"), user_theme="monokai"
        )
        async with app.run_test():
            app._sync_appearance()
            self.assertEqual(app.theme, "monokai")
            self.assertEqual(app.mount_count, 1)
            self.assertFalse(app._follow_appearance)

    async def test_other_config_theme_disables_following(self) -> None:
        """Do not replace a non-Everforest preference in the tracked config."""
        app = self.app_class()(SimpleNamespace(theme="monokai"))
        async with app.run_test():
            app._sync_appearance()
            self.assertEqual(app.theme, "monokai")
            self.assertFalse(app._follow_appearance)

    def test_unset_config_theme_follows_appearance(self) -> None:
        """An unspecified theme adopts the same shared appearance contract."""
        self.appearance.write_text("light\n", encoding="utf-8")
        app = self.app_class()(SimpleNamespace(theme=None))
        self.assertEqual(app.theme, "everforest-light")


if __name__ == "__main__":
    unittest.main()
