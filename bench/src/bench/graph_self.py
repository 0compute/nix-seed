"""Graph the seeded build (build-examples) step by step: one panel per
(example, runner), one line per step of the nix-seed action plus the
consumer's build step, seconds per commit. Runs of the same commit are
one sample: the line is their median and the band their interquartile
range. The x axis is the sequence of commits built, in order of first
run, labelled with the abbreviated commit. Successful jobs only, and
only examples that still exist under examples/ on runners the workflow's
matrix still lists."""

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
    configure,
    current_examples,
    draw_series,
    matrix_os,
    medians,
    save,
)

configure()

WORKFLOW = "build-examples"
# the composite action's steps in order, then the consumer's own build.
# `pull seed` is what `mount seed` was called before the cache existed.
STEPS = ("seed digest", "cache pull", "mount seed", "post cache pull", "build")
RENAMED = {"pull seed": "mount seed"}

app = typer.Typer(add_completion=False)

# (example, os) -> step -> commit ordinal -> seconds of each run
Samples = dict[tuple[str, str], dict[str, dict[int, list[float]]]]


def load(
    source: Path, examples: set[str], runners: set[str]
) -> tuple[list[str], Samples]:
    runs: dict[int, tuple[str, str]] = {}
    rows: list[tuple[int, str, str, str, float]] = []
    with source.open(newline="") as f:
        for row in csv.DictReader(f):
            if row["workflow"] != WORKFLOW:
                continue
            run_id = int(row["run_id"])
            step = RENAMED.get(row["step"], row["step"])
            if row["step"] == "run":
                runs[run_id] = (row["created_at"], row["head_sha"])
            elif (
                step in STEPS
                and row["conclusion"] == "success"
                and row["seconds"]
                and row["example"] in examples
                and row["os"] in runners
            ):
                rows.append(
                    (
                        run_id,
                        row["example"],
                        row["os"],
                        step,
                        float(row["seconds"]),
                    )
                )
    ordinal = commit_order(runs)
    samples: Samples = defaultdict(
        lambda: defaultdict(lambda: defaultdict(list))
    )
    for run_id, example, os, step, secs in rows:
        _, sha = runs[run_id]
        samples[example, os][step][ordinal[sha]].append(secs)
    return list(ordinal), samples


def render(source: Path, out: Path, examples: Path, workflows: Path) -> None:
    commits, samples = load(
        source, current_examples(examples), matrix_os(workflows, WORKFLOW)
    )
    lanes = sorted(samples)
    fig, axes = plt.subplots(
        len(lanes), 1, figsize=(16, 4 * len(lanes)), layout="constrained"
    )
    for ax, lane in zip(axes, lanes, strict=True):
        shown: list[float] = []
        for step in STEPS:
            if step not in samples[lane]:
                continue
            points = medians(samples[lane][step])
            shown += [v for _, v in points]
            draw_series(ax, points, step)
        cap(ax, shown)
        ax.set_xticks(
            range(len(commits)),
            [sha[:7] for sha in commits],
            rotation=90,
            fontsize="x-small",
        )
        example, os = lane
        ax.set_title(
            f"{example} on {os}: seconds per step, successful runs. "
            "dots: median per commit (hollow: outlier); line: rolling "
            f"median of {WINDOW} commits; y capped at 2 x p95"
        )
        ax.set_ylabel("seconds")
        ax.set_xlabel("commits in order of first run")
        ax.grid(alpha=0.3)
        ax.legend(
            title="step",
            fontsize="small",
            loc="upper left",
            bbox_to_anchor=(1, 1),
        )
    fig.suptitle(f"{source.name}: {WORKFLOW}, one line per step")
    save(fig, out)


@app.command()
def main(
    source: Path = Path("bench/workflows.csv"),
    out: Path = Path("bench/self.svg"),
    examples: Path = Path("examples"),
    workflows: Path = Path(".github/workflows"),
) -> None:
    """Graph the build-examples steps from SOURCE (bench-workflows) into
    OUT, for the examples under EXAMPLES on the runners WORKFLOWS lists."""
    render(source, out, examples, workflows)
    print(out)


if __name__ == "__main__":
    app()
