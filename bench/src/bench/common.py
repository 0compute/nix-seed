"""Shared by the graph commands: which series to show, how runs of one
commit are summarised, and how figures are written."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from statistics import quantiles

import matplotlib
import yaml
from matplotlib.figure import Figure

WORKFLOWS = ("build-examples", "build-cache-nix-examples", "build-raw-examples")


def configure() -> None:
    """Headless, and byte-reproducible SVGs: element ids are hashed from a
    fixed salt instead of a random one, and `save` drops the date."""
    matplotlib.use("Agg")
    matplotlib.rcParams["svg.hashsalt"] = "bench"


def save(fig: Figure, out: Path) -> None:
    fig.savefig(out, metadata={"Date": None})


@dataclass(frozen=True)
class Summary:
    """One series' runs on one commit: median and interquartile range."""

    x: int
    low: float
    mid: float
    high: float


def summarise(samples: dict[int, list[float]]) -> list[Summary]:
    """Runs of one commit are samples of the same thing: noise between
    them becomes band width, a change between commits a step."""
    out = []
    for x, values in sorted(samples.items()):
        if len(values) < 2:
            out.append(Summary(x, values[0], values[0], values[0]))
            continue
        q1, q2, q3 = quantiles(values, n=4)
        out.append(Summary(x, q1, q2, q3))
    return out


def commit_order(runs: dict[int, tuple[str, str]]) -> dict[str, int]:
    """head_sha -> ordinal, commits in order of their first run."""
    ordinal: dict[str, int] = {}
    for _, sha in sorted(runs.values()):
        ordinal.setdefault(sha, len(ordinal))
    return ordinal


def cap(ax: matplotlib.axes.Axes, shown: list[float]) -> None:
    """Stop the y axis at twice the 95th percentile: a series that is an
    outlier in its entirety is cut off rather than flattening every other
    one, while the slowest ordinary series stays in view."""
    if shown:
        ax.set_ylim(0, 2 * quantiles(shown, n=20)[-1])


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
