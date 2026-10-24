"""Permanent observer lifecycle tests; no device or journal side effects."""
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from kanata_guard_session import SessionState


def layer_record(invocation, layer):
    return {"_SYSTEMD_INVOCATION_ID": invocation,
            "MESSAGE": f"[INFO] Entered layer:\n\n(deflayer {layer}\n _ _)"}


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.guard = mock.Mock()
        self.state = SessionState(self.guard)
        self.state.update_service("active", "current")
        self.guard.reset_mock()

    def test_current_navigation_pauses_and_base_restores(self):
        self.state.journal(layer_record("current", "nav"), mock.Mock())
        self.guard.pause.assert_called_once_with()
        self.state.journal(layer_record("current", "base"), mock.Mock())
        self.guard.restore.assert_called_once_with()

    def test_stale_invocation_cannot_pause(self):
        refresh = mock.Mock()
        self.state.journal(layer_record("old", "nav"), refresh)
        refresh.assert_called_once_with()
        self.guard.pause.assert_not_called()

    def test_emergency_exit_restores_without_base_log(self):
        self.state.journal(layer_record("current", "nav"), mock.Mock())
        self.state.update_service("inactive", "current")
        self.assertEqual(self.state.layer, "base")
        self.guard.restore.assert_called_once_with()

    def test_restart_discards_old_layer(self):
        self.state.journal(layer_record("current", "nav"), mock.Mock())
        self.state.update_service("active", "new")
        self.assertEqual(self.state.layer, "base")
        self.guard.restore.assert_called_once_with()
        self.state.journal(layer_record("current", "nav"), mock.Mock())
        self.assertEqual(self.guard.pause.call_count, 1)

    def test_periodic_same_service_preserves_navigation(self):
        self.state.journal(layer_record("current", "nav"), mock.Mock())
        self.state.update_service("active", "current")
        self.assertEqual(self.state.layer, "nav")
        self.guard.restore.assert_not_called()

    def test_compositor_reload_reasserts_pause(self):
        self.state.journal(layer_record("current", "nav"), mock.Mock())
        self.state.compositor_reload()
        self.guard.pause.assert_called_with(force=True)

    def test_history_is_applied_only_once(self):
        for layer in ("nav", "base", "nav"):
            self.state.message(layer_record("current", layer), apply=False)
        self.guard.pause.assert_not_called()
        self.guard.restore.assert_not_called()
        self.state.apply_layer()
        self.guard.pause.assert_called_once_with()

    def test_manager_lifecycle_refreshes_current_state(self):
        refresh = mock.Mock()
        self.state.journal({"UNIT": "kanata.service", "MESSAGE": "Stopped old invocation"}, refresh)
        refresh.assert_called_once_with()
        self.guard.restore.assert_not_called()


if __name__ == "__main__":
    unittest.main()
