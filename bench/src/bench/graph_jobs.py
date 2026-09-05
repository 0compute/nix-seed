"""Graph the collected workflow timings: one panel per matrix lane
(example, runner), one line per build workflow, job wall clock per
commit, so the seeded build sits next to the cache and raw alternatives
on the same scale. Runs of the same commit are one sample, at their
median; the line is a rolling median across commits (see bench.common).
The x axis is the sequence of commits built, in order of first run; only
commits that touched what the consumer runs (the action, bin/, mkseed/,
seed/, the examples' flakes, the build and seed workflows) carry a
label, the rest are unlabelled ticks. Successful jobs only, only
examples that still exist under examples/ on runners the workflow's
matrix still lists, and by default only the last 40 commits."""

from __future__ import annotations

import csv
import subprocess
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import typer

from bench.common import (
    WINDOW,
    WORKFLOWS,
    cap,
    commit_order,
    configure,
    current_examples,
    draw_series,
    matrix_os,
    medians,
    save,
)

configure()

# a commit touching one of these can change what the graph measures;
# lock commits (examples/*/.seed.lock) republish, they do not change it
RELEVANT = (
    "action.yaml",
    "bin",
    "mkseed",
    "seed",
    "examples/*/flake.nix",
    "examples/*/flake.lock",
    ".github/workflows/build-*.yaml",
    ".github/workflows/seed-*.yaml",
)

app = typer.Typer(add_completion=False)

# (example, os) -> workflow -> commit ordinal -> seconds of each run
Lanes = dict[tuple[str, str], dict[str, dict[int, list[float]]]]


def load(
    source: Path, examples: set[str], workflows: Path
) -> tuple[list[str], Lanes]:
    runners = {w: matrix_os(workflows, w) for w in WORKFLOWS}
    # run_id -> (created_at, head_sha), across all three workflows so the
    # commit order is shared
    runs: dict[int, tuple[str, str]] = {}
    rows: list[tuple[int, str, str, str, float]] = []
    with source.open(newline="") as f:
        for row in csv.DictReader(f):
            workflow, run_id = row["workflow"], int(row["run_id"])
            if workflow not in WORKFLOWS:
                continue
            if row["step"] == "run":
                runs[run_id] = (row["created_at"], row["head_sha"])
            elif (
                row["step"] == "job"
                and row["conclusion"] == "success"
                and row["example"] in examples
                and row["os"] in runners[workflow]
            ):
                rows.append(
                    (
                        run_id,
                        row["example"],
                        row["os"],
                        workflow,
                        float(row["seconds"]),
                    )
                )
    ordinal = commit_order(runs)
    lanes: Lanes = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for run_id, example, os, workflow, secs in rows:
        _, sha = runs[run_id]
        lanes[example, os][workflow][ordinal[sha]].append(secs)
    return list(ordinal), lanes


def relevant_commits(repo: Path) -> set[str]:
    """Commits that touched a RELEVANT path, from the repository's log."""
    log = subprocess.check_output(
        ["git", "-C", str(repo), "log", "--format=%H", "--", *RELEVANT],
        text=True,
    )
    return set(log.split())


def render(
    source: Path,
    out: Path,
    examples: Path,
    workflows: Path,
    repo: Path,
    last: int,
) -> None:
    commits, lanes = load(source, current_examples(examples), workflows)
    labelled = relevant_commits(repo)
    first = max(0, len(commits) - last) if last else 0
    fig, axes = plt.subplots(
        len(lanes), 1, figsize=(16, 4 * len(lanes)), layout="constrained"
    )
    for ax, lane in zip(axes, sorted(lanes), strict=True):
        shown: list[float] = []
        for workflow in WORKFLOWS:
            points = [
                (x, v) for x, v in medians(lanes[lane][workflow]) if x >= first
            ]
            if not points:
                continue
            shown += [v for _, v in points]
            draw_series(ax, points, workflow)
        cap(ax, shown)
        ax.set_xlim(first - 0.5, len(commits) - 0.5)
        ax.set_xticks(
            range(first, len(commits)),
            [sha[:7] if sha in labelled else "" for sha in commits[first:]],
            rotation=90,
            fontsize="x-small",
        )
        example, os = lane
        ax.set_title(f"{example} on {os}: job wall clock, successful runs")
        ax.set_ylabel("seconds")
        ax.set_xlabel(
            "commits in order of first run; labelled where the consumer, "
            "the seed or the examples changed"
        )
        ax.grid(alpha=0.3)
        ax.legend(
            title=(
                "workflow\ndots: median per commit (hollow: outlier)\n"
                f"line: rolling median of {WINDOW} commits\n"
                "y capped at 2 x p95"
            ),
            fontsize="small",
            title_fontsize="small",
            loc="upper left",
            bbox_to_anchor=(1, 1),
        )
    fig.suptitle(f"{source.name}: seeded build against the alternatives")
    save(fig, out)


@app.command()
def main(
    source: Path = Path("bench/workflows.csv"),
    out: Path = Path("bench/jobs.svg"),
    examples: Path = Path("examples"),
    workflows: Path = Path(".github/workflows"),
    repo: Path = Path("."),
    last: int = 40,
) -> None:
    """Graph SOURCE (from bench-workflows) into OUT: one panel per lane,
    one line per build workflow, the LAST commits (0 for all), labelled
    where REPO's history says the commit could have changed the result."""
    render(source, out, examples, workflows, repo, last)
    print(out)


if __name__ == "__main__":
    app()
