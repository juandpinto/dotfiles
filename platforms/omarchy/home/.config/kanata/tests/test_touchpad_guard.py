"""Unit tests: no real touchpad toggles or input-device access."""
import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock


PATH = pathlib.Path(__file__).resolve().parents[1] / "spacefn_touchpad_guard.py"
SPEC = importlib.util.spec_from_file_location("spacefn_touchpad_guard", PATH)
guard_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard_module)


class ParserTests(unittest.TestCase):
    def test_ignores_definitions_without_log_header(self):
        parser = guard_module.LayerParser()
        self.assertIsNone(parser.feed("(deflayer nav _ _ left down up rght)"))

    def test_colored_multiline_logs(self):
        parser = guard_module.LayerParser()
        self.assertIsNone(parser.feed("12:00:00 \x1b[34m[INFO]\x1b[0m Entered layer:\n"))
        self.assertIsNone(parser.feed("\n"))
        self.assertEqual(parser.feed("(deflayer nav _ _ left down up rght)\n"), "nav")
        self.assertIsNone(parser.feed("(deflayer base @cap @spfn h j k l)\n"))
        parser.feed("12:00:01 [INFO] Entered layer:\n")
        self.assertEqual(parser.feed("(deflayer base @cap @spfn h j k l)\n"), "base")


    def test_multirow_layer_dump(self):
        parser = guard_module.LayerParser()
        parser.feed("[INFO] Entered layer:\n")
        self.assertEqual(parser.feed("(deflayer nav\n"), "nav")
        self.assertIsNone(parser.feed("  _ _\n"))
        self.assertIsNone(parser.feed("  pgdn pgup home end grv del spc\n"))
        self.assertIsNone(parser.feed("  brdn brup prev pp next mute vold volu\n"))
        self.assertIsNone(parser.feed(")\n"))
        parser.feed("[INFO] Entered layer:\n")
        self.assertEqual(parser.feed("(deflayer base\n"), "base")


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.marker = pathlib.Path(self.temporary.name) / "paused"
        self.calls = []
        self.guard = guard_module.TouchpadGuard(self.marker, "this-trial", self.calls.append)
        patcher = mock.patch.object(guard_module, "restore_enabled", return_value=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_pause_and_restore(self):
        self.guard.pause()
        self.guard.restore()
        self.assertEqual(self.calls, [False, True])
        self.assertFalse(self.marker.exists())

    def test_duplicate_layer_logs_are_idempotent(self):
        self.guard.pause()
        self.guard.pause()
        self.guard.restore()
        self.guard.restore()
        self.assertEqual(self.calls, [False, True])

    def test_marker_exists_before_disable_ipc(self):
        def apply(enabled):
            self.assertTrue(self.guard.owns_marker())
            self.calls.append(enabled)
        self.guard.apply = apply
        self.guard.pause()
        self.assertEqual(self.calls, [False])

    def test_disable_failure_leaves_recovery_marker(self):
        self.guard.apply = mock.Mock(side_effect=RuntimeError("IPC failed"))
        with self.assertRaises(RuntimeError):
            self.guard.pause()
        self.assertTrue(self.guard.owns_marker())
        self.guard.apply = self.calls.append
        self.guard.restore()
        self.assertEqual(self.calls, [True])
        self.assertFalse(self.marker.exists())

    def test_restore_failure_retains_marker(self):
        self.guard.pause()
        self.guard.apply = mock.Mock(side_effect=RuntimeError("IPC failed"))
        with self.assertRaises(RuntimeError):
            self.guard.restore()
        self.assertTrue(self.guard.owns_marker())

    def test_restore_retries_transient_failure(self):
        self.guard.pause()
        self.guard.apply = mock.Mock(side_effect=[RuntimeError("busy"), RuntimeError("busy"), None])
        with mock.patch.object(guard_module.time, "sleep"):
            self.assertTrue(guard_module.restore_with_retry(self.guard))
        self.assertEqual(self.guard.apply.call_count, 3)
        self.assertFalse(self.marker.exists())

    def test_old_watchdog_cannot_restore_new_trial(self):
        self.guard.pause()
        self.marker.write_text("new-trial\n")
        self.guard.restore()
        self.assertEqual(self.calls, [False])
        self.assertEqual(self.marker.read_text(), "new-trial\n")

    def test_respects_explicit_user_disable(self):
        self.guard.pause()
        with mock.patch.object(guard_module, "restore_enabled", return_value=False):
            self.guard.restore()
        self.assertEqual(self.calls, [False, False])
        self.assertFalse(self.marker.exists())

    def test_no_marker_means_no_restore_side_effect(self):
        self.guard.restore()
        self.assertEqual(self.calls, [])

    def test_watchdog_can_be_armed_without_touching_device(self):
        child = guard_module.arm_watchdog(self.marker, "this-trial")
        try:
            self.assertIsNone(child.poll())
            self.assertFalse(self.marker.exists())
        finally:
            child.terminate()
            child.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
