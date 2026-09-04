"""Graph the collected workflow timings: one panel per build workflow, one
line per matrix job (example, runner), job wall clock per commit. Runs
of the same commit are one sample: the line is their median and the band
their interquartile range. The x axis is the sequence of commits built,
in order of first run, labelled with the abbreviated commit. Successful
jobs only, so a cancelled or failed run does not read as a fast one, and
only examples that still exist under examples/ on runners the workflow's
matrix still lists."""

from __future__ import annotations

import csv
from collections import defaultdict
from dataclasses import dataclass, field
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

app = typer.Typer(add_completion=False)


@dataclass
class Panel:
    """One workflow: its commits in order of first run, and per job the
    job seconds of every run, keyed by commit ordinal."""

    commits: list[str] = field(default_factory=list)
    jobs: dict[str, dict[int, list[float]]] = field(
        default_factory=lambda: defaultdict(lambda: defaultdict(list))
    )


def panels(
    source: Path, examples: set[str], workflows: Path
) -> dict[str, Panel]:
    runners = {w: matrix_os(workflows, w) for w in WORKFLOWS}
    # workflow -> run_id -> (created_at, head_sha)
    runs: dict[str, dict[int, tuple[str, str]]] = defaultdict(dict)
    samples: dict[str, list[tuple[int, str, float]]] = defaultdict(list)
    with source.open(newline="") as f:
        for row in csv.DictReader(f):
            workflow, run_id = row["workflow"], int(row["run_id"])
            if row["step"] == "run":
                runs[workflow][run_id] = (row["created_at"], row["head_sha"])
            elif (
                row["step"] == "job"
                and row["conclusion"] == "success"
                and row["example"] in examples
                and row["os"] in runners[workflow]
            ):
                job = f"{row['example']} {row['os']}"
                samples[workflow].append((run_id, job, float(row["seconds"])))
    result: dict[str, Panel] = {}
    for workflow in WORKFLOWS:
        ordinal = commit_order(runs[workflow])
        panel = Panel(list(ordinal))
        for run_id, job, secs in samples[workflow]:
            _, sha = runs[workflow][run_id]
            panel.jobs[job][ordinal[sha]].append(secs)
        result[workflow] = panel
    return result


def render(source: Path, out: Path, examples: Path, workflows: Path) -> None:
    data = panels(source, current_examples(examples), workflows)
    # constrained layout makes room for the legends beside the axes
    # instead of shrinking the axes under them
    fig, axes = plt.subplots(
        len(WORKFLOWS),
        1,
        figsize=(16, 5 * len(WORKFLOWS)),
        layout="constrained",
    )
    for ax, workflow in zip(axes, WORKFLOWS, strict=True):
        panel = data[workflow]
        shown: list[float] = []
        for job, samples in sorted(panel.jobs.items()):
            points = medians(samples)
            shown += [v for _, v in points]
            draw_series(ax, points, job)
        cap(ax, shown)
        ax.set_xticks(
            range(len(panel.commits)),
            [sha[:7] for sha in panel.commits],
            rotation=90,
            fontsize="x-small",
        )
        ax.set_title(
            f"{workflow}: wall clock per matrix job, successful runs. "
            "dots: median per commit (hollow: outlier); line: rolling "
            f"median of {WINDOW} commits; y capped at 2 x p95"
        )
        ax.set_ylabel("job wall clock (seconds)")
        ax.set_xlabel("commits in order of first run")
        ax.grid(alpha=0.3)
        ax.legend(
            title="example, runner",
            fontsize="small",
            loc="upper left",
            bbox_to_anchor=(1, 1),
        )
    fig.suptitle(
        f"{source.name}: build workflows, one line per (example, runner)"
    )
    save(fig, out)


@app.command()
def main(
    source: Path = Path("bench/workflows.csv"),
    out: Path = Path("bench/jobs.svg"),
    examples: Path = Path("examples"),
    workflows: Path = Path(".github/workflows"),
) -> None:
    """Graph SOURCE (from bench-workflows) into OUT, for the examples that
    still exist under EXAMPLES on the runners the WORKFLOWS matrices list."""
    render(source, out, examples, workflows)
    print(out)


if __name__ == "__main__":
    app()
