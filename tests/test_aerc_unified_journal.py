"""Tests for the durable unified-mail undo journal."""

from __future__ import annotations

import stat
import sys
import tempfile
import unittest
from pathlib import Path

DOTFILES = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DOTFILES / ".local" / "bin"))

from aerc_unified_journal import (  # noqa: E402
    MoveJournal,
    MoveRecord,
    Transaction,
    sha256_file,
)


class MoveJournalTest(unittest.TestCase):
    """Cover journal persistence and one-step undo state transitions."""

    def test_round_trip_and_latest_action(self) -> None:
        """Persist each transition and expose only the newest action for undo."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            journal = MoveJournal(Path(temporary_directory) / "state")
            transaction = Transaction.create(
                "archive",
                [
                    MoveRecord(
                        message_id="example@example.com",
                        account="icloud",
                        source="/mail/icloud/Inbox/cur/source",
                        destination="/mail/icloud/Archive/cur/destination",
                        sha256="a" * 64,
                    )
                ],
            )

            with journal.locked():
                history = journal.load()
                history.append(transaction)
                journal.save(history)

                transaction.moves[0].moved = True
                transaction.state = "complete"
                journal.save(history)

            with journal.locked():
                history = journal.load()
                latest = journal.latest_action(history)
                self.assertIsNotNone(latest)
                assert latest is not None
                self.assertEqual(latest.id, transaction.id)
                self.assertEqual(latest.state, "complete")
                self.assertTrue(latest.has_remaining_undo())

                latest.state = "undo_pending"
                journal.save(history)
                latest.moves[0].undone = True
                latest.state = "undone"
                journal.save(history)

            with journal.locked():
                history = journal.load()
                latest = journal.latest_action(history)
                self.assertIsNotNone(latest)
                assert latest is not None
                self.assertEqual(latest.state, "undone")
                self.assertFalse(latest.has_remaining_undo())

            self.assertEqual(stat.S_IMODE(journal.journal_path.stat().st_mode), 0o600)

    def test_sha256_file(self) -> None:
        """Use message content, rather than a mutable Maildir filename, as identity."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            message = Path(temporary_directory) / "message"
            message.write_bytes(b"message body\n")
            self.assertEqual(
                sha256_file(message),
                "c9e04ff93383aff530ba9875b24ab0c74d7360549eb7c7fd2aec5689a7288b6d",
            )


if __name__ == "__main__":
    unittest.main()
