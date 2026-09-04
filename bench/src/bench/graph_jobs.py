"""Graph the collected workflow timings: one panel per build workflow, one
line per matrix job (example, runner), job wall clock per commit. Runs
of the same commit are one sample: the line is their median and the band
their interquartile range, so noise between runs of one commit shows as
band width and a change between commits shows as a step. The x axis is
the sequence of commits built, in order of first run, labelled with the
abbreviated commit. Successful jobs only, so a cancelled or failed run
does not read as a fast one, and only examples that still exist under
examples/ on runners the workflow's matrix still lists."""

from __future__ import annotations

import csv
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from statistics import quantiles

import matplotlib
import matplotlib.pyplot as plt
import typer
import yaml

matplotlib.use("Agg")
# element ids are hashed from this salt instead of a random one, so the
# same CSV gives the same SVG bytes (the creation date is dropped too)
matplotlib.rcParams["svg.hashsalt"] = "bench"

WORKFLOWS = ("build-examples", "build-cache-nix-examples", "build-raw-examples")

app = typer.Typer(add_completion=False)


@dataclass
class Panel:
    """One workflow: its commits in order of first run, and per job the
    job seconds of every run, keyed by commit ordinal."""

    commits: list[str] = field(default_factory=list)
    jobs: dict[str, dict[int, list[float]]] = field(
        default_factory=lambda: defaultdict(lambda: defaultdict(list))
    )


@dataclass(frozen=True)
class Summary:
    """A job's runs on one commit: median and interquartile range."""

    x: int
    low: float
    mid: float
    high: float


def summarise(samples: dict[int, list[float]]) -> list[Summary]:
    out = []
    for x, values in sorted(samples.items()):
        if len(values) < 2:
            out.append(Summary(x, values[0], values[0], values[0]))
            continue
        q1, q2, q3 = quantiles(values, n=4)
        out.append(Summary(x, q1, q2, q3))
    return out


def current_examples(examples: Path) -> set[str]:
    """Example names (flake dirs under EXAMPLES, as the matrix names them,
    e.g. "hello/innocent") that still exist: deleted examples are history,
    not a series worth a line."""
    return {
        flake.parent.relative_to(examples).as_posix()
        for flake in examples.glob("**/flake.nix")
    }


def matrix_os(workflows: Path, workflow: str) -> set[str]:
    """The runners the workflow's build matrix lists today: runners it
    used to run on are history, not a series worth a line."""
    with (workflows / f"{workflow}.yaml").open() as f:
        return set(
            yaml.safe_load(f)["jobs"]["build"]["strategy"]["matrix"]["os"]
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
        panel = Panel()
        ordinal: dict[str, int] = {}
        for _, sha in sorted(runs[workflow].values()):
            if sha not in ordinal:
                ordinal[sha] = len(panel.commits)
                panel.commits.append(sha)
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
            points = summarise(samples)
            shown += [p.mid for p in points]
            xs = [p.x for p in points]
            (line,) = ax.plot(
                xs, [p.mid for p in points], marker=".", linewidth=1, label=job
            )
            ax.fill_between(
                xs,
                [p.low for p in points],
                [p.high for p in points],
                color=line.get_color(),
                alpha=0.15,
                linewidth=0,
            )
        # the axis stops at twice the 95th percentile: a series that is an
        # outlier in its entirety (a one-off multi-minute example) is cut
        # off rather than flattening every other one, while the slowest
        # ordinary series stays in view
        if shown:
            ax.set_ylim(0, 2 * quantiles(shown, n=20)[-1])
        ax.set_xticks(
            range(len(panel.commits)),
            [sha[:7] for sha in panel.commits],
            rotation=90,
            fontsize="x-small",
        )
        ax.set_title(
            f"{workflow}: wall clock per matrix job, successful runs, "
            "median per commit with interquartile band, y capped at 2 x p95"
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
    # no creation date in the SVG: the same CSV must give the same bytes
    fig.savefig(out, metadata={"Date": None})


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
