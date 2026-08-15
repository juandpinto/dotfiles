"""Isolated filesystem tests for unified archive/trash undo behavior."""

from __future__ import annotations

import runpy
import tempfile
import unittest
from pathlib import Path
from typing import Any

from aerc_unified_journal import JournalError, MoveJournal

DOTFILES = Path(__file__).resolve().parents[1]
HELPER = DOTFILES / ".local" / "bin" / "notmuch-unified-file"
MESSAGE_ID = "message@example.test"


def load_helper() -> dict[str, Any]:
    """Load the executable helper without running its command-line entry point."""
    return runpy.run_path(str(HELPER), run_name="notmuch_unified_file_test")


class UnifiedFileUndoTest(unittest.TestCase):
    """Exercise journaling with a disposable Maildir and no real notmuch call."""

    def setUp(self) -> None:
        """Create a minimal iCloud Maildir and inject isolated helper globals."""
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.maildir = self.root / "mail"
        self.source = self.maildir / "icloud" / "Inbox" / "cur" / "message,U=42:2,S"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(b"Message-ID: <message@example.test>\n\nbody\n")

        self.helper = load_helper()
        self.helper_globals = self.helper["move_messages"].__globals__
        self.helper_globals["MAILDIR"] = self.maildir
        self.helper_globals["LOG_PATH"] = self.root / "helper.log"
        self.helper_globals["UNDO_STATE_DIR"] = self.root / "state"
        self.helper_globals["files_for_message_id"] = lambda _message_id: [
            self.source
        ]
        self.helper_globals["log"] = lambda _message: None

    def tearDown(self) -> None:
        """Remove only this test's TemporaryDirectory after each test."""
        self.temporary_directory.cleanup()

    def test_archive_then_undo_restores_exact_original_path(self) -> None:
        """A forward move and undo preserve original folder and Maildir name."""
        move_messages = self.helper["move_messages"]
        undo_last_action = self.helper["undo_last_action"]
        destination = self.maildir / "icloud" / "Archive" / "cur" / "message:2,S"

        touched, resolved = move_messages([MESSAGE_ID], "archive")
        self.assertTrue(resolved)
        self.assertEqual(touched, {"icloud"})
        self.assertFalse(self.source.exists())
        self.assertTrue(destination.exists())

        journal = MoveJournal(self.root / "state")
        with journal.locked():
            transaction = journal.latest_action(journal.load())
        self.assertIsNotNone(transaction)
        assert transaction is not None
        self.assertEqual(transaction.state, "complete")
        self.assertTrue(transaction.moves[0].moved)

        touched, error = undo_last_action()
        self.assertEqual(touched, {"icloud"})
        self.assertIsNone(error)
        self.assertTrue(self.source.exists())
        self.assertFalse(destination.exists())

        with journal.locked():
            transaction = journal.latest_action(journal.load())
        self.assertIsNotNone(transaction)
        assert transaction is not None
        self.assertEqual(transaction.state, "undone")
        self.assertTrue(transaction.moves[0].undone)

    def test_bulk_action_undoes_every_account_as_one_transaction(self) -> None:
        """A marked/bulk action restores every completed move together."""
        second_id = "second@example.test"
        second_source = (
            self.maildir / "gmail" / "Inbox" / "cur" / "second,U=7:2,S"
        )
        second_source.parent.mkdir(parents=True)
        second_source.write_bytes(b"Message-ID: <second@example.test>\n\nbody\n")
        second_destination = self.maildir / "gmail" / "Archive" / "cur" / "second:2,S"
        self.helper_globals["files_for_message_id"] = lambda message_id: {
            MESSAGE_ID: [self.source],
            second_id: [second_source],
        }[message_id]

        move_messages = self.helper["move_messages"]
        undo_last_action = self.helper["undo_last_action"]
        touched, resolved = move_messages([MESSAGE_ID, second_id], "archive")

        self.assertTrue(resolved)
        self.assertEqual(touched, {"icloud", "gmail"})
        self.assertFalse(self.source.exists())
        self.assertFalse(second_source.exists())
        self.assertTrue(second_destination.exists())

        journal = MoveJournal(self.root / "state")
        with journal.locked():
            transaction = journal.latest_action(journal.load())
        self.assertIsNotNone(transaction)
        assert transaction is not None
        self.assertEqual(len(transaction.moves), 2)

        touched, error = undo_last_action()
        self.assertEqual(touched, {"icloud", "gmail"})
        self.assertIsNone(error)
        self.assertTrue(self.source.exists())
        self.assertTrue(second_source.exists())
        self.assertFalse(second_destination.exists())

    def test_undo_recovers_a_crash_after_a_forward_rename(self) -> None:
        """A persisted forward intent makes the rename recoverable after a crash."""
        move_messages = self.helper["move_messages"]
        undo_last_action = self.helper["undo_last_action"]
        destination = self.maildir / "icloud" / "Archive" / "cur" / "message:2,S"

        move_messages([MESSAGE_ID], "archive")
        journal = MoveJournal(self.root / "state")
        with journal.locked():
            history = journal.load()
            transaction = journal.latest_action(history)
            self.assertIsNotNone(transaction)
            assert transaction is not None
            transaction.state = "pending"
            transaction.moves[0].forward_started = True
            transaction.moves[0].moved = False
            journal.save(history)

        touched, error = undo_last_action()
        self.assertEqual(touched, {"icloud"})
        self.assertIsNone(error)
        self.assertTrue(self.source.exists())
        self.assertFalse(destination.exists())

    def test_undo_refuses_to_overwrite_an_original_path(self) -> None:
        """A conflicting source file leaves the moved message untouched."""
        move_messages = self.helper["move_messages"]
        undo_last_action = self.helper["undo_last_action"]
        destination = self.maildir / "icloud" / "Archive" / "cur" / "message:2,S"

        move_messages([MESSAGE_ID], "archive")
        self.source.write_bytes(b"unrelated replacement\n")

        with self.assertRaises(JournalError):
            undo_last_action()

        self.assertTrue(self.source.exists())
        self.assertTrue(destination.exists())


if __name__ == "__main__":
    unittest.main()
