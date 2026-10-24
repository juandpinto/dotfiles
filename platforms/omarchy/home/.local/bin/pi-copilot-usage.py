#!/usr/bin/env -S uv run --offline --no-project --python /usr/bin/python3
"""Feed Pi/Copilot token stats and account allowance into Omarchy's agent panel."""

# %% Imports and numeric helpers
import http.client
import json
import math
import os
import sys
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any


def token_count(value: Any) -> int:
    try:
        return max(0, int(value or 0))
    except (TypeError, ValueError, OverflowError):
        return 0


def local_day(value: Any) -> str | None:
    try:
        if isinstance(value, (int, float)):
            seconds = value / 1000 if value > 10_000_000_000 else value
            stamp = datetime.fromtimestamp(seconds).astimezone()
        else:
            stamp = datetime.fromisoformat(str(value)).astimezone()
        return stamp.date().isoformat()
    except (TypeError, ValueError, OverflowError, OSError):
        return None


# %% Local metadata only; never persist prompts, responses, or credentials
def collect_stats(sessions_dir: Path, now: datetime) -> dict[str, Any]:
    today = now.date().isoformat()
    days = {
        (now - timedelta(days=offset)).date().isoformat(): 0
        for offset in range(6, -1, -1)
    }
    models: dict[str, dict[str, int]] = {}
    today_models: dict[str, int] = {}
    sessions: set[Path] = set()
    today_sessions: set[Path] = set()
    active_days: set[str] = set()
    seen: set[tuple[str, str]] = set()
    fields = {
        "inputTokens": "input",
        "outputTokens": "output",
        "cacheReadInputTokens": "cacheRead",
        "cacheCreationInputTokens": "cacheWrite",
    }

    for path in sorted(sessions_dir.rglob("*.jsonl")):
        with path.open(encoding="utf-8", errors="replace") as handle:
            for index, line in enumerate(handle):
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    # A running session may have an unfinished final line.
                    continue
                if not isinstance(entry, dict):
                    continue
                if entry.get("type") == "message":
                    message = entry.get("message")
                    if not isinstance(message, dict):
                        continue
                    if message.get("role") != "assistant":
                        continue
                elif entry.get("type") == "usage":
                    message = entry
                else:
                    # Summary/tool usage without a provider cannot safely be attributed.
                    continue
                if message.get("provider") != "github-copilot":
                    continue
                usage = message.get("usage")
                if not isinstance(usage, dict):
                    continue
                bucket = {
                    target: token_count(usage.get(source))
                    for target, source in fields.items()
                }
                # Reasoning is already included in output; totalTokens includes cached tokens.
                total = sum(bucket.values())
                if not total:
                    total = bucket["inputTokens"] = token_count(
                        usage.get("totalTokens")
                    )
                if not total:
                    continue
                stamp = entry.get("timestamp") or message.get("timestamp")
                day = local_day(stamp)
                if day is None:
                    continue
                # Forks/clones copy earlier entries: count each actual call only once.
                key = (str(entry.get("id") or f"{path}:{index}"), str(stamp))
                if key in seen:
                    continue
                seen.add(key)
                model = str(message.get("model") or "unknown")
                model_totals = models.setdefault(
                    model, dict.fromkeys(fields, 0)
                )
                for field, value in bucket.items():
                    model_totals[field] += value
                sessions.add(path)
                active_days.add(day)
                if day in days:
                    days[day] += total
                if day == today:
                    today_sessions.add(path)
                    today_models[model] = today_models.get(model, 0) + total

    return {
        "hasLocalStats": bool(sessions),
        # API/tool-loop calls are not user prompts; don't mislabel them as such.
        "hasPromptStats": False,
        "totalSessions": len(sessions),
        "todaySessions": len(today_sessions),
        "activeDays": len(active_days),
        "activeDates": sorted(active_days),
        "todayTotalTokens": days[today],
        "todayTokensByModel": today_models,
        "recentDays": [
            {"date": day, "messageCount": total} for day, total in days.items()
        ],
        "modelUsage": models,
    }


# %% Read-only Copilot allowance query using Pi's existing GitHub OAuth token
def copilot_token(agent_dir: Path) -> str:
    token = os.environ.get("COPILOT_GITHUB_TOKEN", "")
    if token:
        return token
    auth = json.loads((agent_dir / "auth.json").read_text())
    credential = auth.get("github-copilot", {})
    if credential.get("type") == "oauth":
        # 'access' is a short-lived Copilot token; 'refresh' is the GitHub token.
        return str(credential.get("refresh") or "")
    if credential.get("type") == "api_key":
        token = str(credential.get("key") or "")
        # Never execute auth.json secret-manager commands from a background job.
        return "" if token.startswith("!") else token
    return ""


def allowance_fields(account: dict[str, Any]) -> dict[str, Any]:
    fields: dict[str, Any] = {
        "tierLabel": str(account.get("copilot_plan") or "").replace("_", " "),
        "limits": [],
        "usageStatusText": "",
        "authHelpText": "",
    }
    quota = (account.get("quota_snapshots") or {}).get("premium_interactions")
    if not isinstance(quota, dict):
        raise TypeError("No premium allowance in account response")
    if quota.get("unlimited") is True:
        return fields
    remaining = quota.get("percent_remaining")
    if not isinstance(remaining, (int, float)) or not math.isfinite(remaining):
        raise ValueError("No valid remaining percentage")
    reset = (
        quota.get("quota_reset_at")
        or account.get("quota_reset_date_utc")
        or account.get("quota_reset_date")
    )
    resets_at = ""
    if reset:
        stamp = datetime.fromisoformat(str(reset))
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=UTC)
        resets_at = stamp.isoformat()
    fields["limits"] = [
        {
            "label": "Monthly premium allowance",
            "title": "Monthly premium",
            "percent": max(0.0, min(1.0, 1 - remaining / 100)),
            "resetsAt": resets_at,
        }
    ]
    return fields


def fetch_allowance(agent_dir: Path) -> dict[str, Any]:
    unavailable = {
        "tierLabel": "",
        "limits": [],
        "usageStatusText": "Copilot allowance unavailable",
        "authHelpText": "Local Pi token usage is still shown. Sign in with /login github-copilot in Pi if needed.",
    }
    try:
        token = copilot_token(agent_dir)
    except (OSError, ValueError, AttributeError):
        return unavailable
    if not token:
        return unavailable

    # HTTPSConnection deliberately does not follow redirects with the credential.
    connection = http.client.HTTPSConnection("api.github.com", timeout=10)
    try:
        connection.request(
            "GET",
            "/copilot_internal/user",
            headers={
                "Authorization": f"token {token}",
                "Accept": "application/json",
                "User-Agent": "pi-copilot-usage-monitor",
            },
        )
        response = connection.getresponse()
        if response.status != 200:
            unavailable["authHelpText"] = (
                f"GitHub returned HTTP {response.status}. "
                + unavailable["authHelpText"]
            )
            return unavailable
        return allowance_fields(json.loads(response.read()))
    except (
        OSError,
        http.client.HTTPException,
        ValueError,
        TypeError,
        AttributeError,
    ):
        # Never log raw responses, request headers, credentials, or exception text.
        return unavailable
    finally:
        connection.close()


# %% Publish only the usage record, atomically, outside the dotfiles repository
def write_record(record: dict[str, Any], usage_dir: Path) -> None:
    usage_dir.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(
        prefix=".copilot-", suffix=".tmp", dir=usage_dir
    )
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(record, handle, separators=(",", ":"))
            handle.write("\n")
        temporary.replace(usage_dir / "copilot.json")
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    home = Path.home()
    agent_dir = Path(
        os.environ.get("PI_CODING_AGENT_DIR") or home / ".pi/agent"
    )
    sessions_dir = Path(
        os.environ.get("PI_CODING_AGENT_SESSION_DIR") or agent_dir / "sessions"
    )
    state_dir = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
    now = datetime.now().astimezone()
    try:
        record = {
            "schemaVersion": 1,
            "id": "copilot",
            "name": "GitHub Copilot (Pi)",
            "updatedAt": now.isoformat(),
            "ready": True,
            **collect_stats(sessions_dir, now),
            **fetch_allowance(agent_dir),
        }
        write_record(record, state_dir / "omarchy/agents/usage")
    except (OSError, ValueError):
        print(
            "Pi/Copilot usage update failed; the existing record was preserved.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
