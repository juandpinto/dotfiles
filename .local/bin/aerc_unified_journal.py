"""Durable local transaction storage for unified-mail moves.

The journal is deliberately independent of aerc and notmuch. It records only
local file-move intent and progress, so an interrupted action can be safely
inspected or resumed without guessing from an application log.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import tempfile
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1


class JournalError(RuntimeError):
    """Raised when persisted undo state is invalid or cannot be used safely."""


@dataclass
class MoveRecord:
    """One reversible Maildir rename within a grouped user action.

    Attributes:
        message_id: RFC 5322 Message-ID used only to recover from a Maildir
            filename change made by mbsync after the initial move.
        account: Real account directory below the shared Maildir root.
        source: Original absolute path before the action.
        destination: Planned absolute path after the action.
        sha256: Content digest used to reject ambiguous recovery candidates.
        forward_started: Whether durable state was saved immediately before the
            forward rename. It allows recovery from a process crash in the
            narrow interval between the rename and its completion marker.
        moved: Whether the forward rename completed and can therefore be
            reversed.
        undo_started: Whether durable state was saved immediately before the
            reverse rename.
        undone: Whether the reverse rename completed.
    """

    message_id: str
    account: str
    source: str
    destination: str
    sha256: str
    forward_started: bool = False
    moved: bool = False
    undo_started: bool = False
    undone: bool = False

    def to_dict(self) -> dict[str, Any]:
        """Serialize this record into the on-disk journal format."""
        return {
            "message_id": self.message_id,
            "account": self.account,
            "source": self.source,
            "destination": self.destination,
            "sha256": self.sha256,
            "forward_started": self.forward_started,
            "moved": self.moved,
            "undo_started": self.undo_started,
            "undone": self.undone,
        }

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> MoveRecord:
        """Deserialize and validate one journal move record."""
        required = {"message_id", "account", "source", "destination", "sha256"}
        if not required <= value.keys():
            raise JournalError("move record is missing required fields")
        return cls(
            message_id=str(value["message_id"]),
            account=str(value["account"]),
            source=str(value["source"]),
            destination=str(value["destination"]),
            sha256=str(value["sha256"]),
            forward_started=bool(value.get("forward_started", False)),
            moved=bool(value.get("moved", False)),
            undo_started=bool(value.get("undo_started", False)),
            undone=bool(value.get("undone", False)),
        )


@dataclass
class Transaction:
    """One grouped archive, trash, or future folder-move action.

    The states are intentionally explicit:

    - ``pending``: the durable intent exists; a forward move may be in progress.
    - ``complete``: all attempted forward moves have finished.
    - ``undo_pending``: a reverse move may be in progress.
    - ``undone``: every completed forward move was restored.
    """

    id: str
    action: str
    created_at: str
    state: str
    moves: list[MoveRecord] = field(default_factory=list)

    @classmethod
    def create(cls, action: str, moves: list[MoveRecord]) -> Transaction:
        """Create a durable pending transaction before any file is renamed."""
        return cls(
            id=str(uuid.uuid4()),
            action=action,
            created_at=datetime.now(UTC).isoformat(),
            state="pending",
            moves=moves,
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize this transaction into the on-disk journal format."""
        return {
            "id": self.id,
            "action": self.action,
            "created_at": self.created_at,
            "state": self.state,
            "moves": [move.to_dict() for move in self.moves],
        }

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> Transaction:
        """Deserialize and validate one journal transaction."""
        required = {"id", "action", "created_at", "state", "moves"}
        if not required <= value.keys():
            raise JournalError("transaction is missing required fields")
        state = str(value["state"])
        if state not in {"pending", "complete", "undo_pending", "undone"}:
            raise JournalError(f"unknown transaction state: {state}")
        moves = value["moves"]
        if not isinstance(moves, list):
            raise JournalError("transaction moves must be a list")
        return cls(
            id=str(value["id"]),
            action=str(value["action"]),
            created_at=str(value["created_at"]),
            state=state,
            moves=[MoveRecord.from_dict(move) for move in moves],
        )

    def has_completed_moves(self) -> bool:
        """Return whether at least one forward move finished."""
        return any(move.moved for move in self.moves)

    def has_remaining_undo(self) -> bool:
        """Return whether a completed forward move still needs restoring."""
        return any(move.moved and not move.undone for move in self.moves)


class MoveJournal:
    """Atomically persist and serialize a single unified-action history.

    The caller holds ``locked()`` while planning, renaming, and updating a
    transaction. This prevents an archive/trash action and an undo action from
    observing or changing the journal concurrently.
    """

    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir
        self.journal_path = state_dir / "journal.json"
        self.lock_path = state_dir / "journal.lock"

    def ensure_state_dir(self) -> None:
        """Create the private state directory with owner-only permissions."""
        self.state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.state_dir.chmod(0o700)

    @contextmanager
    def locked(self) -> Iterator[None]:
        """Acquire the action lock until the caller's transaction is settled."""
        self.ensure_state_dir()
        with self.lock_path.open("a+", encoding="utf-8") as lock_file:
            self.lock_path.chmod(0o600)
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def load(self) -> list[Transaction]:
        """Load all transaction history, rejecting malformed state safely."""
        if not self.journal_path.exists():
            return []
        try:
            raw = json.loads(self.journal_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise JournalError(f"cannot read undo journal: {error}") from error
        if not isinstance(raw, dict) or raw.get("version") != SCHEMA_VERSION:
            raise JournalError("undo journal has an unsupported format")
        transactions = raw.get("transactions")
        if not isinstance(transactions, list):
            raise JournalError("undo journal transactions must be a list")
        return [Transaction.from_dict(transaction) for transaction in transactions]

    def save(self, transactions: list[Transaction]) -> None:
        """Atomically save the full journal and make its file private."""
        self.ensure_state_dir()
        payload = {
            "version": SCHEMA_VERSION,
            "transactions": [transaction.to_dict() for transaction in transactions],
        }
        descriptor, temporary_name = tempfile.mkstemp(
            dir=self.state_dir,
            prefix=".journal-",
            suffix=".json",
        )
        temporary_path = Path(temporary_name)
        try:
            os.fchmod(descriptor, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
                json.dump(payload, temporary_file, indent=2, sort_keys=True)
                temporary_file.write("\n")
                temporary_file.flush()
                os.fsync(temporary_file.fileno())
            os.replace(temporary_path, self.journal_path)
            self._sync_state_dir()
        finally:
            if temporary_path.exists():
                temporary_path.unlink()

    def latest_action(self, transactions: list[Transaction]) -> Transaction | None:
        """Return only the newest action; this intentionally implements one-step undo."""
        return transactions[-1] if transactions else None

    def _sync_state_dir(self) -> None:
        """Flush the directory entry after atomically replacing the journal."""
        try:
            descriptor = os.open(self.state_dir, os.O_RDONLY)
        except OSError:
            return
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def sha256_file(path: Path) -> str:
    """Return a content digest for an existing message file."""
    digest = hashlib.sha256()
    with path.open("rb") as message_file:
        while chunk := message_file.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()
