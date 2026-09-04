"""Shared by the graph commands: which series to show, how runs of one
commit are summarised, and how figures are written."""

from __future__ import annotations

from pathlib import Path
from statistics import median, quantiles

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


# commits either side of a point that count as its neighbourhood, for
# both the outlier test and the trend line: a real shift outlasts it, a
# stalled run does not
WINDOW = 5
# a point further than this many (scaled) median absolute deviations
# from its neighbourhood's median is a stall, not a trend
DEVIATIONS = 3.0

# (commit ordinal, seconds)
Point = tuple[int, float]


def medians(samples: dict[int, list[float]]) -> list[Point]:
    """Runs of one commit are samples of the same thing: one point per
    commit, at their median."""
    return [(x, median(values)) for x, values in sorted(samples.items())]


def neighbourhoods(values: list[float]) -> list[list[float]]:
    half = WINDOW // 2
    return [values[max(0, i - half) : i + half + 1] for i in range(len(values))]


def hampel(values: list[float]) -> tuple[list[float], list[bool]]:
    """Hampel filter: replace a point that sits DEVIATIONS scaled MADs
    from its neighbourhood's median with that median, and say which. The
    MAD is floored at 5% of the median so a flat run of identical values
    does not turn the next tenth of a second into an outlier."""
    cleaned, flagged = [], []
    for value, local in zip(values, neighbourhoods(values), strict=True):
        centre = median(local)
        mad = 1.4826 * median(abs(v - centre) for v in local)
        outlier = abs(value - centre) > DEVIATIONS * max(mad, 0.05 * centre)
        cleaned.append(centre if outlier else value)
        flagged.append(outlier)
    return cleaned, flagged


def rolling_median(values: list[float]) -> list[float]:
    return [median(local) for local in neighbourhoods(values)]


def draw_series(
    ax: matplotlib.axes.Axes, points: list[Point], label: str
) -> None:
    """One series in two layers: every commit's median as a faint dot
    (hollow where the Hampel filter called it an outlier), and the trend,
    a rolling median of the cleaned values, as the line that carries the
    label."""
    xs = [x for x, _ in points]
    raw = [v for _, v in points]
    cleaned, flagged = hampel(raw)
    (line,) = ax.plot(xs, rolling_median(cleaned), linewidth=1.5, label=label)
    colour = line.get_color()
    kept = [(x, v) for x, v, f in zip(xs, raw, flagged, strict=True) if not f]
    dropped = [(x, v) for x, v, f in zip(xs, raw, flagged, strict=True) if f]
    if kept:
        ax.plot(*zip(*kept, strict=True), ".", color=colour, alpha=0.3)
    if dropped:
        ax.plot(
            *zip(*dropped, strict=True),
            "o",
            markerfacecolor="none",
            color=colour,
            alpha=0.5,
            markersize=4,
        )


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
