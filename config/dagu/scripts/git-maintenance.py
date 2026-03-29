#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
"""Git maintenance: gc and optional cleanup for repos under ~/src."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

STATE_FILE = Path(os.environ.get("GIT_MAINT_STATE_FILE") or (Path.home() / ".local/share/dagu/git-maintenance.json"))
SRC_DIR = Path(os.environ.get("GIT_MAINT_SRC_DIR") or (Path.home() / "src"))
HC_HOST = "https://hc.k.oneill.net"
CHECK_NAME = "dagu-cleanup-git"
GC_INTERVAL_DAYS = 7
CLEANUP_GRACE_DAYS = 7


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def repo_weekday(name: str) -> int:
    """Deterministic weekday (0=Monday .. 6=Sunday) for a repo name."""
    digest = hashlib.sha256(name.encode()).hexdigest()
    return int(digest, 16) % 7


def staggered_timestamp(weekday: int, after_success: datetime) -> datetime:
    """Return a timestamp for the most recent occurrence of `weekday` within the past week.

    Used after a successful first run to stagger repos so they come due on
    different days going forward, rather than all on the same day.
    """
    days_since = (after_success.weekday() - weekday) % 7
    if days_since == 0:
        days_since = 7
    target = after_success - timedelta(days=days_since)
    return target.replace(hour=0, minute=0, second=0, microsecond=0)


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except json.JSONDecodeError:
            print(f"WARNING: corrupt state file {STATE_FILE}, starting fresh", file=sys.stderr)
    return {"repos": {}}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_FILE.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(state, f, indent=2)
            f.write("\n")
        os.rename(tmp, STATE_FILE)
    except BaseException:
        os.unlink(tmp)
        raise


def discover_repos() -> list[Path]:
    """Find git repos directly under ~/src."""
    repos = []
    if not SRC_DIR.is_dir():
        return repos
    for entry in sorted(SRC_DIR.iterdir()):
        if entry.is_dir() and (entry / ".git").exists():
            repos.append(entry)
    return repos


def is_due(repo_name: str, repo_state: dict, today_weekday: int, current_time: datetime, force: bool) -> bool:
    if force:
        return True
    last_success = repo_state.get("last_gc_success")
    if not last_success:
        return True  # Never run before — always due
    assigned = repo_weekday(repo_name)
    if today_weekday != assigned:
        return False
    elapsed = current_time - parse_iso(last_success)
    return elapsed >= timedelta(days=GC_INTERVAL_DAYS)


def run_gc(repo: Path) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["git", "gc", "--aggressive"],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=7200,
        )
        output = result.stdout + result.stderr
        return result.returncode == 0, output.strip()
    except subprocess.TimeoutExpired:
        return False, "git gc timed out after 2h"


def run_cleanup(repo: Path) -> tuple[bool, str] | None:
    cleanup = repo / "scripts" / "cleanup"
    if not (cleanup.exists() and os.access(cleanup, os.X_OK)):
        return None
    try:
        result = subprocess.run(
            [str(cleanup)],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=300,
        )
        output = result.stdout + result.stderr
        return result.returncode == 0, output.strip()
    except subprocess.TimeoutExpired:
        return False, "scripts/cleanup timed out after 5m"


def ping_healthchecks(report: str, failed: bool) -> None:
    api_key = os.environ.get("DAGU_HEALTHCHECK_API_KEY", "")
    ping_key = os.environ.get("DAGU_HEALTHCHECK_PING_KEY", "")

    if not api_key or not ping_key:
        print("WARNING: healthcheck keys not set, skipping ping", file=sys.stderr)
        return

    # Create check if it doesn't exist (idempotent)
    create_payload = json.dumps({
        "api_key": api_key,
        "name": CHECK_NAME,
        "timeout": 604800,
        "grace": 86400,
        "tags": "dagu",
        "channels": "*",
        "unique": ["name"],
    })
    subprocess.run(
        ["curl", "-sf", "-m", "10", "--retry", "3",
         f"{HC_HOST}/api/v1/checks/",
         "--data-binary", "@-",
         "-H", "Content-Type: application/json"],
        input=create_payload,
        capture_output=True,
        text=True,
    )

    # Ping with report body
    suffix = "/fail" if failed else ""
    url = f"{HC_HOST}/ping/{ping_key}/{CHECK_NAME}{suffix}"
    subprocess.run(
        ["curl", "-fsS", "-m", "10", "--retry", "5", "-o", "/dev/null",
         "--data-binary", "@-", url],
        input=report,
        text=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Git repo maintenance")
    parser.add_argument("--force", action="store_true", help="Process all repos regardless of schedule")
    args = parser.parse_args()

    state = load_state()
    repos = discover_repos()
    current_time = now_utc()
    today_weekday = current_time.weekday()

    gc_failures: list[str] = []
    cleanup_escalations: list[str] = []
    report_lines: list[str] = []
    processed = 0
    skipped = 0

    for repo in repos:
        name = repo.name
        repo_state = state["repos"].setdefault(name, {})

        is_first_run = "last_gc_success" not in repo_state

        if not is_due(name, repo_state, today_weekday, current_time, args.force):
            skipped += 1
            continue

        processed += 1
        report_lines.append(f"=== {name} ===")

        # git gc
        gc_ok, gc_output = run_gc(repo)
        repo_state["last_gc_run"] = iso(current_time)
        if gc_ok:
            if is_first_run and not args.force:
                # Stagger timestamp so repos come due on different weekdays
                assigned = repo_weekday(name)
                repo_state["last_gc_success"] = iso(staggered_timestamp(assigned, current_time))
            else:
                repo_state["last_gc_success"] = iso(current_time)
            report_lines.append("  git gc: OK")
        else:
            gc_failures.append(name)
            report_lines.append(f"  git gc: FAILED\n{gc_output}")

        # scripts/cleanup
        cleanup_result = run_cleanup(repo)
        if cleanup_result is not None:
            cleanup_ok, cleanup_output = cleanup_result
            repo_state["last_cleanup_run"] = iso(current_time)
            if cleanup_ok:
                repo_state["last_cleanup_success"] = iso(current_time)
                repo_state.pop("first_cleanup_failure", None)
                report_lines.append("  scripts/cleanup: OK")
            else:
                if "first_cleanup_failure" not in repo_state:
                    repo_state["first_cleanup_failure"] = iso(current_time)
                first_fail = parse_iso(repo_state["first_cleanup_failure"])
                days_failing = (current_time - first_fail).days
                if days_failing >= CLEANUP_GRACE_DAYS:
                    cleanup_escalations.append(f"{name} (failing {days_failing}d)")
                    report_lines.append(f"  scripts/cleanup: FAILED (escalated, {days_failing}d)\n{cleanup_output}")
                else:
                    report_lines.append(f"  scripts/cleanup: FAILED (grace, {days_failing}d/{CLEANUP_GRACE_DAYS}d)\n{cleanup_output}")

    # Summary
    report_lines.append("")
    report_lines.append("=== Summary ===")
    report_lines.append(f"Repos processed: {processed}")
    report_lines.append(f"Repos skipped (not due): {skipped}")
    if gc_failures:
        report_lines.append(f"GC failures: {', '.join(gc_failures)}")
    if cleanup_escalations:
        report_lines.append(f"Cleanup escalations: {', '.join(cleanup_escalations)}")

    report = "\n".join(report_lines)
    print(report)

    # Determine overall status
    failed = bool(gc_failures) or bool(cleanup_escalations)

    # Save state before pinging (in case ping fails)
    save_state(state)

    # Ping healthchecks with full report
    ping_healthchecks(report, failed)

    if failed:
        if gc_failures:
            print(f"\nGC failures: {', '.join(gc_failures)}", file=sys.stderr)
        if cleanup_escalations:
            print(f"\nCleanup escalations: {', '.join(cleanup_escalations)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
