"""Isolated collector tests: no desktop changes, credentials, or network access."""

# %% Load the authored collector without executing its entry point
import importlib.util
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

SCRIPT = (
    Path(__file__).resolve().parents[1] / "home/.local/bin/pi-copilot-usage.py"
)
SPEC = importlib.util.spec_from_file_location("pi_copilot_usage", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)


# %% Synthetic session and account fixtures
class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.now = datetime.now().astimezone().replace(hour=12)

    def entry(self, entry_id="response", **changes):
        result = {
            "type": "message",
            "id": entry_id,
            "timestamp": self.now.isoformat(),
            "message": {
                "role": "assistant",
                "provider": "github-copilot",
                "model": "gpt-test",
                "content": "PRIVATE MESSAGE CONTENT",
                "usage": {
                    "input": 100,
                    "output": 20,
                    "cacheRead": 300,
                    "cacheWrite": 10,
                    "reasoning": 5,
                    "totalTokens": 430,
                },
            },
        }
        result.update(changes)
        return result

    def session(self, name, entries):
        path = self.root / "sessions" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("".join(json.dumps(item) + "\n" for item in entries))
        return path

    def stats(self):
        return collector.collect_stats(self.root / "sessions", self.now)

    def account(self, **quota_changes):
        return {
            "copilot_plan": "individual_pro",
            "quota_reset_date_utc": "2026-11-01T00:00:00.000Z",
            "quota_snapshots": {
                "premium_interactions": {
                    "percent_remaining": 25.0,
                    "unlimited": False,
                    **quota_changes,
                }
            },
        }

    def test_tokens_cache_and_reasoning_are_not_double_counted(self):
        self.session("one.jsonl", [self.entry()])
        stats = self.stats()
        self.assertEqual(stats["todayTotalTokens"], 430)
        self.assertEqual(stats["modelUsage"]["gpt-test"]["outputTokens"], 20)
        self.assertEqual(stats["totalSessions"], 1)
        self.assertFalse(stats["hasPromptStats"])
        self.assertNotIn("PRIVATE MESSAGE CONTENT", json.dumps(stats))

    def test_other_providers_are_excluded_even_with_the_same_model(self):
        entry = self.entry()
        entry["message"]["provider"] = "openai-codex"
        self.session("other.jsonl", [entry])
        self.assertEqual(self.stats()["todayTotalTokens"], 0)
        self.assertEqual(self.stats()["totalSessions"], 0)

    def test_forked_history_is_counted_once(self):
        original = self.entry()
        self.session("a-original.jsonl", [original])
        self.session("b-fork.jsonl", [original, self.entry("new-response")])
        self.assertEqual(self.stats()["todayTotalTokens"], 860)
        self.assertEqual(self.stats()["totalSessions"], 2)

    def test_explicit_usage_entries_count_without_reading_tool_results(self):
        self.session(
            "usage.jsonl",
            [
                {
                    "type": "usage",
                    "id": "warm",
                    "timestamp": self.now.isoformat(),
                    "provider": "github-copilot",
                    "model": "gpt-test",
                    "usage": {"totalTokens": 12},
                },
                {"type": "compaction", "usage": {"totalTokens": 999}},
            ],
        )
        self.assertEqual(self.stats()["todayTotalTokens"], 12)

    def test_old_usage_stays_in_totals_but_not_today(self):
        entry = self.entry(
            timestamp=(self.now - timedelta(days=10)).isoformat()
        )
        self.session("old.jsonl", [entry])
        stats = self.stats()
        self.assertEqual(stats["todayTotalTokens"], 0)
        self.assertEqual(stats["totalSessions"], 1)
        self.assertEqual(
            sum(day["messageCount"] for day in stats["recentDays"]), 0
        )
        self.assertEqual(stats["modelUsage"]["gpt-test"]["inputTokens"], 100)

    def test_malformed_and_incomplete_lines_do_not_abort_scan(self):
        path = self.session("active.jsonl", [None, [], self.entry()])
        with path.open("a") as handle:
            handle.write('{"unfinished":')
        self.assertEqual(self.stats()["todayTotalTokens"], 430)

    def test_missing_usage_invalid_timestamps_and_invalid_counts_are_safe(self):
        entry = self.entry()
        entry["message"]["usage"] = None
        invalid_time = self.entry("invalid-time", timestamp="not-a-date")
        self.session("invalid.jsonl", [entry, invalid_time])
        self.assertEqual(self.stats()["todayTotalTokens"], 0)
        for number in (None, "bad", -5, float("nan"), float("inf")):
            self.assertEqual(collector.token_count(number), 0)

    def test_account_percentage_and_reset_are_used_without_guessing_units(self):
        fields = collector.allowance_fields(self.account())
        self.assertEqual(fields["limits"][0]["percent"], 0.75)
        self.assertEqual(
            fields["limits"][0]["resetsAt"], "2026-11-01T00:00:00+00:00"
        )
        self.assertEqual(fields["usageStatusText"], "")

    def test_exhausted_and_unlimited_allowances(self):
        exhausted = collector.allowance_fields(
            self.account(percent_remaining=0, remaining=-11870)
        )
        self.assertEqual(exhausted["limits"][0]["percent"], 1.0)
        unlimited = collector.allowance_fields(self.account(unlimited=True))
        self.assertEqual(unlimited["limits"], [])

    def test_unknown_quota_shape_is_not_reported_as_zero_usage(self):
        for account in ({}, self.account(percent_remaining=None)):
            with self.assertRaises((ValueError, TypeError)):
                collector.allowance_fields(account)

    def test_oauth_uses_the_github_token_not_the_short_lived_copilot_token(
        self,
    ):
        auth = {
            "github-copilot": {
                "type": "oauth",
                "refresh": "GITHUB_SECRET",
                "access": "COPILOT_SECRET",
            }
        }
        (self.root / "auth.json").write_text(json.dumps(auth))
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                collector.copilot_token(self.root), "GITHUB_SECRET"
            )
        self.assertEqual(
            json.loads((self.root / "auth.json").read_text()), auth
        )

    def test_secret_commands_are_never_executed(self):
        auth = {"github-copilot": {"type": "api_key", "key": "!secret-command"}}
        (self.root / "auth.json").write_text(json.dumps(auth))
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(collector.copilot_token(self.root), "")

    def test_request_goes_only_to_github_and_does_not_publish_credentials(self):
        with (
            mock.patch.object(
                collector, "copilot_token", return_value="SECRET"
            ),
            mock.patch.object(
                collector.http.client, "HTTPSConnection"
            ) as https,
        ):
            connection = https.return_value
            response = connection.getresponse.return_value
            response.status = 200
            response.read.return_value = json.dumps(self.account()).encode()
            fields = collector.fetch_allowance(self.root)
            https.assert_called_once_with("api.github.com", timeout=10)
            args, kwargs = connection.request.call_args
            self.assertEqual(args, ("GET", "/copilot_internal/user"))
            self.assertEqual(kwargs["headers"]["Authorization"], "token SECRET")
            self.assertNotIn("SECRET", json.dumps(fields))
            connection.close.assert_called_once()

    def test_http_failure_preserves_local_only_mode_and_hides_response_body(
        self,
    ):
        with (
            mock.patch.object(
                collector, "copilot_token", return_value="SECRET"
            ),
            mock.patch.object(
                collector.http.client, "HTTPSConnection"
            ) as https,
        ):
            response = https.return_value.getresponse.return_value
            response.status = 401
            response.read.return_value = b"PRIVATE RESPONSE BODY"
            fields = collector.fetch_allowance(self.root)
            self.assertEqual(fields["limits"], [])
            self.assertIn("HTTP 401", fields["authHelpText"])
            self.assertNotIn("PRIVATE", json.dumps(fields))
            self.assertNotIn("SECRET", json.dumps(fields))
            response.read.assert_not_called()

    def test_missing_credentials_and_network_failure_are_nonfatal(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            fields = collector.fetch_allowance(self.root)
            self.assertEqual(fields["limits"], [])
        with (
            mock.patch.object(
                collector, "copilot_token", return_value="SECRET"
            ),
            mock.patch.object(
                collector.http.client, "HTTPSConnection"
            ) as https,
        ):
            https.return_value.request.side_effect = OSError("SECRET")
            fields = collector.fetch_allowance(self.root)
            self.assertNotIn("SECRET", json.dumps(fields))
            self.assertEqual(
                fields["usageStatusText"], "Copilot allowance unavailable"
            )

    def test_atomic_record_is_private_and_leaves_no_discoverable_temporary_json(
        self,
    ):
        usage_dir = self.root / "usage"
        collector.write_record({"id": "copilot", "totalSessions": 1}, usage_dir)
        collector.write_record({"id": "copilot", "totalSessions": 2}, usage_dir)
        path = usage_dir / "copilot.json"
        self.assertEqual(json.loads(path.read_text())["totalSessions"], 2)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(
            [item.name for item in usage_dir.iterdir()], ["copilot.json"]
        )


if __name__ == "__main__":
    unittest.main()
