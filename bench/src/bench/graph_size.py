"""Graph the collected artifact sizes: one panel per matrix lane
(example, runner), one line per delivery mechanism, size in MB per
commit, so the seed sits next to the actions/cache archive on the same
scale. Runs of the same commit are one sample, at their median; the
line is a rolling median across commits (see bench.common). The x axis
is the sequence of commits built, in order of first run; only commits
that touched what the consumer runs carry a label, the rest are
unlabelled ticks. Successful jobs only, only examples that still exist
under examples/ on runners the workflow's matrix still lists, and by
default only the last 40 commits."""

from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import typer

from bench.common import (
    WINDOW,
    cap,
    commit_order,
    commit_ticks,
    configure,
    current_examples,
    draw_series,
    matrix_os,
    medians,
    relevant_commits,
    save,
)

configure()

app = typer.Typer(add_completion=False)

# workflow -> the step whose bytes column is this graph's series for it.
# build-raw-examples fetches nothing of its own, so it has no size series.
STEPS = {
    "build-examples": "seed size",
    "build-cache-nix-examples": "cache size",
}

# (example, os) -> workflow -> commit ordinal -> megabytes of each run
Lanes = dict[tuple[str, str], dict[str, dict[int, list[float]]]]


def load(
    source: Path, examples: set[str], workflows: Path
) -> tuple[list[str], Lanes]:
    runners = {w: matrix_os(workflows, w) for w in STEPS}
    # run_id -> (created_at, head_sha), across both workflows so the
    # commit order is shared
    runs: dict[int, tuple[str, str]] = {}
    rows: list[tuple[int, str, str, str, float]] = []
    with source.open(newline="") as f:
        for row in csv.DictReader(f):
            workflow, run_id = row["workflow"], int(row["run_id"])
            if workflow not in STEPS:
                continue
            if row["step"] == "run":
                runs[run_id] = (row["created_at"], row["head_sha"])
            elif (
                row["step"] == STEPS[workflow]
                and row["conclusion"] == "success"
                and row["example"] in examples
                and row["os"] in runners[workflow]
                and row["bytes"]
            ):
                rows.append(
                    (
                        run_id,
                        row["example"],
                        row["os"],
                        workflow,
                        int(row["bytes"]) / 1_000_000,
                    )
                )
    ordinal = commit_order(runs)
    lanes: Lanes = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for run_id, example, os, workflow, megabytes in rows:
        _, sha = runs[run_id]
        lanes[example, os][workflow][ordinal[sha]].append(megabytes)
    return list(ordinal), lanes


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
        for workflow in STEPS:
            points = [
                (x, v) for x, v in medians(lanes[lane][workflow]) if x >= first
            ]
            if not points:
                continue
            shown += [v for _, v in points]
            draw_series(ax, points, workflow)
        cap(ax, shown)
        commit_ticks(ax, commits, first, labelled)
        example, os = lane
        ax.set_title(f"{example} on {os}: artifact size, successful runs")
        ax.set_ylabel("size (MB)")
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
    fig.suptitle(f"{source.name}: seed size against the actions/cache archive")
    save(fig, out)


@app.command()
def main(
    source: Path = Path("bench/workflows.csv"),
    out: Path = Path("bench/size.svg"),
    examples: Path = Path("examples"),
    workflows: Path = Path(".github/workflows"),
    repo: Path = Path("."),
    last: int = 40,
) -> None:
    """Graph SOURCE (from bench-workflows) into OUT: one panel per lane,
    one line per delivery mechanism, the LAST commits (0 for all),
    labelled where REPO's history says the commit could have changed
    the result."""
    render(source, out, examples, workflows, repo, last)
    print(out)


if __name__ == "__main__":
    app()
