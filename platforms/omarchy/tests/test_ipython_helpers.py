"""Routing tests: no real terminal escapes, desktop viewers, or REPL injection."""
import os
import pathlib
import types
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[3]
HELPER = ROOT / '.ipython/profile_default/startup/00-nvim-helpers.py'


def load_helper():
    module = types.ModuleType('nvim_helpers')
    module.get_ipython = lambda: None
    exec(compile(HELPER.read_text(), str(HELPER), 'exec'), module.__dict__)
    return module


class RenderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = load_helper()

    def test_kitty_in_tmux_uses_stream_and_placeholders(self):
        h = self.helper
        with mock.patch.dict(os.environ, {'TMUX': 'test', 'KITTY_PID': '1'}, clear=True), \
             mock.patch.object(h, '_KITTEN', '/usr/bin/kitten'), \
             mock.patch.object(h.subprocess, 'run') as run:
            run.return_value.returncode = 0
            self.assertTrue(h._send_kitty_icat(b'PNG'))
            args = run.call_args.args[0]
            self.assertIn('--passthrough=tmux', args)
            self.assertIn('--transfer-mode=stream', args)
            self.assertEqual(run.call_args.kwargs['input'], b'PNG')

    def test_bare_kitty_does_not_wrap_tmux(self):
        h = self.helper
        with mock.patch.dict(os.environ, {'TERM': 'xterm-kitty'}, clear=True), \
             mock.patch.object(h, '_KITTEN', '/usr/bin/kitten'), \
             mock.patch.object(h.subprocess, 'run') as run:
            run.return_value.returncode = 0
            self.assertTrue(h._send_kitty_icat(b'PNG'))
            self.assertIn('--passthrough=none', run.call_args.args[0])

    def test_wezterm_keeps_existing_renderer(self):
        h = self.helper
        with mock.patch.dict(os.environ, {'TERM_PROGRAM': 'WezTerm'}, clear=True), \
             mock.patch.object(h, '_KITTEN', '/usr/bin/kitten'), \
             mock.patch.object(h.subprocess, 'run') as run:
            self.assertFalse(h._send_kitty_icat(b'PNG'))
            run.assert_not_called()

    def test_missing_kitten_fails_open(self):
        h = self.helper
        with mock.patch.object(h, '_KITTEN', None):
            self.assertFalse(h._send_kitty_icat(b'PNG'))

    def test_kitten_timeout_falls_back(self):
        h = self.helper
        with mock.patch.dict(os.environ, {'KITTY_PID': '1'}, clear=True), \
             mock.patch.object(h, '_KITTEN', '/usr/bin/kitten'), \
             mock.patch.object(h.subprocess, 'run', side_effect=h.subprocess.TimeoutExpired('kitten', 15)):
            self.assertFalse(h._send_kitty_icat(b'PNG'))

    def test_system_viewer_is_os_specific(self):
        h = self.helper
        for platform, prefix in [('darwin', ['open', '-a', 'Preview']), ('linux', ['xdg-open'])]:
            with self.subTest(platform=platform), mock.patch.object(h.sys, 'platform', platform), \
                 mock.patch.object(h.subprocess, 'Popen') as popen:
                h._open_in_preview(b'PNG')
                args = popen.call_args.args[0]
                self.assertEqual(args[:-1], prefix)
                pathlib.Path(args[-1]).unlink()

    def test_show_fig_prefers_modern_kitty(self):
        h = self.helper
        fig = mock.Mock()
        fig.savefig.side_effect = lambda stream, **kwargs: stream.write(b'PNG')
        with mock.patch.object(h, '_send_kitty_icat', return_value=True) as modern, \
             mock.patch.object(h, '_send_sixel_image') as sixel:
            h.show_fig(fig)
            modern.assert_called_once_with(b'PNG')
            sixel.assert_not_called()

    def test_preview_bypasses_all_inline_renderers(self):
        h = self.helper
        fig = mock.Mock()
        fig.savefig.side_effect = lambda stream, **kwargs: stream.write(b'PNG')
        with mock.patch.object(h, '_send_kitty_icat') as modern, \
             mock.patch.object(h, '_open_in_preview') as viewer:
            h.show_fig(fig, preview=True)
            viewer.assert_called_once_with(b'PNG')
            modern.assert_not_called()


if __name__ == '__main__':
    unittest.main()
