"""Graph the seeded build (build-examples) step by step: one panel per
(example, runner), one stacked bar per commit whose segments are the
steps of the nix-seed action plus the consumer's build step, in
execution order, so the bar is the job and each segment that step's
share of it. Runs of the same commit are one sample, at their median;
nothing is smoothed across commits. The x axis is the sequence of
commits built, in order of first run, labelled with the abbreviated
commit. Successful jobs only, and only examples that still exist under
examples/ on runners the workflow's matrix still lists."""

from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import typer

from bench.common import (
    cap,
    commit_order,
    configure,
    current_examples,
    matrix_os,
    medians,
    save,
)

configure()

WORKFLOW = "build-examples"
# the composite action's steps and the consumer's own build, in execution
# order (the post step runs after the build). `pull seed` is what `mount
# seed` was called before the cache existed.
STEPS = ("seed digest", "cache pull", "mount seed", "build", "post cache pull")
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
    xs = range(len(commits))
    for ax, lane in zip(axes, lanes, strict=True):
        # one bar per commit, one segment per step in execution order:
        # the bar is the job, each segment that step's share of it. the
        # only aggregation is the median across the commit's runs.
        bottom = [0.0] * len(commits)
        for step in STEPS:
            heights = [0.0] * len(commits)
            for x, secs in medians(samples[lane].get(step, {})):
                heights[x] = secs
            ax.bar(xs, heights, bottom=bottom, width=0.8, label=step)
            bottom = [b + h for b, h in zip(bottom, heights, strict=True)]
        cap(ax, [b for b in bottom if b])
        ax.set_xticks(
            xs, [sha[:7] for sha in commits], rotation=90, fontsize="x-small"
        )
        example, os = lane
        ax.set_title(
            f"{example} on {os}: seconds per step, stacked; median across "
            "the commit's successful runs; y capped at 2 x p95"
        )
        ax.set_ylabel("seconds")
        ax.set_xlabel("commits in order of first run")
        ax.grid(alpha=0.3, axis="y")
        ax.legend(
            title="step",
            fontsize="small",
            loc="upper left",
            bbox_to_anchor=(1, 1),
        )
    fig.suptitle(f"{source.name}: {WORKFLOW}, steps stacked per commit")
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
