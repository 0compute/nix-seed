"""Graph the collected workflow timings: one panel per build workflow, one
line per matrix job (example, runner), job wall clock per run. The x
axis is the sequence of runs, labelled with the abbreviated commit each
run built, so idle hours do not stretch the plot and a change in the
code lines up with a change in the timings. Successful jobs only, so a
cancelled or failed run does not read as a fast one, and only examples
that still exist under examples/."""

from __future__ import annotations

import csv
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from statistics import median, quantiles

import matplotlib
import matplotlib.pyplot as plt
import typer

matplotlib.use("Agg")

WORKFLOWS = ("build-examples", "build-cache-nix-examples", "build-raw-examples")
# runs per rolling median; odd, so the middle run is a real sample
WINDOW = 5

# (run ordinal within the workflow, job seconds)
Point = tuple[int, float]

app = typer.Typer(add_completion=False)


@dataclass
class Panel:
    """One workflow: its runs in time order and one series per job."""

    # (created_at, run_id, head_sha) sorted -> ordinal is the list index
    runs: list[tuple[str, int, str]] = field(default_factory=list)
    jobs: dict[str, list[Point]] = field(
        default_factory=lambda: defaultdict(list)
    )

    def ticks(self) -> tuple[list[int], list[str]]:
        """One tick per commit, at the first run that built it."""
        positions, labels = [], []
        previous = None
        for ordinal, (_, _, sha) in enumerate(self.runs):
            if sha != previous:
                positions.append(ordinal)
                labels.append(sha[:7])
                previous = sha
        return positions, labels


def current_examples(examples: Path) -> set[str]:
    """Example names (flake dirs under EXAMPLES, as the matrix names them,
    e.g. "hello/innocent") that still exist: deleted examples are history,
    not a series worth a line."""
    return {
        flake.parent.relative_to(examples).as_posix()
        for flake in examples.glob("**/flake.nix")
    }


def panels(source: Path, examples: set[str]) -> dict[str, Panel]:
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
            ):
                job = f"{row['example']} {row['os']}"
                samples[workflow].append((run_id, job, float(row["seconds"])))
    result: dict[str, Panel] = {}
    for workflow in WORKFLOWS:
        panel = Panel(
            sorted(
                (when, run_id, sha)
                for run_id, (when, sha) in runs[workflow].items()
            )
        )
        ordinal = {run_id: i for i, (_, run_id, _) in enumerate(panel.runs)}
        for run_id, job, secs in samples[workflow]:
            panel.jobs[job].append((ordinal[run_id], secs))
        for values in panel.jobs.values():
            values.sort()
        result[workflow] = panel
    return result


def smoothed(values: list[Point], window: int = WINDOW) -> list[Point]:
    """Rolling median over WINDOW neighbouring runs: a single stalled job
    (a cold cache, a slow runner) no longer dominates the axis, while a
    real shift, which lasts more than half a window, survives."""
    half = window // 2
    return [
        (
            x,
            median(secs for _, secs in values[max(0, i - half) : i + half + 1]),
        )
        for i, (x, _) in enumerate(values)
    ]


def render(source: Path, out: Path, examples: Path) -> None:
    data = panels(source, current_examples(examples))
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
        for job, values in sorted(panel.jobs.items()):
            values = smoothed(values)
            shown += [secs for _, secs in values]
            ax.plot(
                [x for x, _ in values],
                [secs for _, secs in values],
                marker=".",
                linewidth=1,
                label=job,
            )
        # the axis stops at twice the 95th percentile: a series that is an
        # outlier in its entirety (a one-off multi-minute example) is cut
        # off rather than flattening every other one, while the slowest
        # ordinary series stays in view
        if shown:
            ax.set_ylim(0, 2 * quantiles(shown, n=20)[-1])
        positions, labels = panel.ticks()
        ax.set_xticks(positions, labels, rotation=90, fontsize="x-small")
        ax.set_title(
            f"{workflow}: wall clock per matrix job, successful runs, "
            f"rolling median of {WINDOW}, y capped at 2 x p95"
        )
        ax.set_ylabel("job wall clock (seconds)")
        ax.set_xlabel("runs in time order, labelled by the commit built")
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
    fig.savefig(out)


@app.command()
def main(
    source: Path = Path("bench/workflows.csv"),
    out: Path = Path("bench/workflows.svg"),
    examples: Path = Path("examples"),
) -> None:
    """Graph SOURCE (from bench-workflows) into OUT, for the examples that
    still exist under EXAMPLES."""
    render(source, out, examples)
    print(out)


if __name__ == "__main__":
    app()
