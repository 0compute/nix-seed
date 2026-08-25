#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3 python3Packages.typer

"""
Estimate nixpkgs unstable toolchain rebuild cadence from a local git checkout.

Usage:
  python3 scripts/toolchain_churn.py /path/to/nixpkgs [--since YYYY-MM-DD]

Notes:
- Offline only: this script reads local git history and does not fetch.
- It counts change days from non-merge commits on HEAD history that touch
  toolchain-critical paths and reports event cadence, including per-path counts
  and commits.
- Output is YAML for stable machine parsing.
"""

from __future__ import annotations

import contextlib
import datetime as dt
import subprocess
import sys
from pathlib import Path

import typer

DEFAULT_PATHS = [
    "pkgs/stdenv",
    "pkgs/build-support/cc-wrapper",
    "pkgs/development/compilers/gcc",
    "pkgs/development/compilers/llvm",
    "pkgs/development/libraries/glibc",
    "pkgs/development/tools/misc/binutils",
    "pkgs/os-specific/linux/kernel-headers",
]
DATE_FMT = "%Y-%m-%d"
DEFAULT_SINCE = "2024-01-01"


def run_git(repo: Path, args: list[str]) -> str:
    cmd = ["git", "-C", str(repo), *args]
    return subprocess.check_output(cmd, text=True, stderr=subprocess.PIPE)


def parse_date(value: str) -> dt.date:
    return dt.datetime.strptime(value, DATE_FMT).date()


def head_branch(repo: Path) -> str:
    branch = "HEAD"
    with contextlib.suppress(subprocess.CalledProcessError):
        branch = run_git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]).strip()
    return branch


def commits_for_paths(
    repo: Path,
    since: str,
    paths: list[str],
) -> list[tuple[str, dt.date]]:
    raw = run_git(
        repo,
        [
            "log",
            "--no-merges",
            "--date=short",
            "--pretty=format:%H\t%ad",
            f"--since={since}",
            "HEAD",
            "--",
            *paths,
        ],
    )
    commits: list[tuple[str, dt.date]] = []
    for line in raw.splitlines():
        row = line.strip()
        if not row:
            continue
        commit, day = row.split("\t", 1)
        commits.append((commit, parse_date(day)))
    return commits


def collapse_commits_by_day(
    commits: list[tuple[str, dt.date]],
) -> list[tuple[str, dt.date]]:
    # Keep the most recent commit seen for each day.
    selected_by_day: dict[dt.date, str] = {}
    ordered_days: list[dt.date] = []
    for commit, day in commits:
        if day in selected_by_day:
            continue
        selected_by_day[day] = commit
        ordered_days.append(day)
    return [(selected_by_day[day], day) for day in ordered_days]


def sort_events_desc(
    events: list[tuple[str, dt.date]],
) -> list[tuple[str, dt.date]]:
    return sorted(events, key=lambda item: item[1], reverse=True)


def main(repo: Path, since: str) -> int:
    if not repo.exists():
        print(f"error: repo path does not exist: {repo}", file=sys.stderr)
        return 2

    try:
        since_date = parse_date(since)
    except ValueError:
        print("error: --since must be YYYY-MM-DD", file=sys.stderr)
        return 2

    try:
        commits = commits_for_paths(repo, since, DEFAULT_PATHS)
        per_path_commits = {
            path: sort_events_desc(
                collapse_commits_by_day(commits_for_paths(repo, since, [path])),
            )
            for path in DEFAULT_PATHS
        }
    except subprocess.CalledProcessError as e:
        print("error: failed to read git history", file=sys.stderr)
        if e.stderr:
            print(e.stderr.strip(), file=sys.stderr)
        return 2

    events = sort_events_desc(collapse_commits_by_day(commits))

    today = dt.date.today()
    span_days = max(1, (today - since_date).days)
    span_weeks = span_days / 7.0
    weekly = int(round(len(events) / span_weeks))

    print(f"repo: {repo}")
    print(f"branch: {head_branch(repo)}")
    print(f"since: {since_date.isoformat()}")
    print(f"weekly: {weekly}")
    if events:
        last_hash, last_day = events[0]
        print("last:")
        print(f"  date: {last_day.isoformat()}")
        print(f"  commit: {last_hash}")
    else:
        print("last: null")
    print("events:")
    print(f"  count: {len(events)}")
    print("  paths:")
    for path in DEFAULT_PATHS:
        path_events = per_path_commits[path]
        print(f"    - path: {path}")
        print(f"      count: {len(path_events)}")
        if path_events:
            print("      commits:")
            for commit, _day in path_events:
                print(f"        - {commit}")
        else:
            print("      commits: []")

    return 0


app = typer.Typer(
    add_completion=False,
    context_settings={"help_option_names": ["-h", "--help"]},
)


@app.command()
def cli(
    repo: Path = typer.Argument(..., help="Local nixpkgs git checkout"),
    since: str = typer.Option(
        DEFAULT_SINCE,
        "--since",
        help="Lower date bound (inclusive), format YYYY-MM-DD",
    ),
) -> None:
    raise typer.Exit(main(repo=repo, since=since))


if __name__ == "__main__":
    app()
