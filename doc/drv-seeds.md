# drv-baked seeds: built, measured, removed

Status: **removed**. This records what the variant did, what it cost, and
the measurements that ended it, so the idea is not rediscovered from
scratch.

## What it was

A second seed variant. Instead of baking every flake input source, it
baked the *instantiated recipes* -- the transitive `.drv` closure of the
harvested outputs -- plus a `.seed/drvs.json` manifest naming them. The
consumer ran `nix-store --realise` rather than `nix build`: no
evaluation at all, and no nixpkgs source tree in the blob.

Because a `.drv` is a closed recipe, a source change could not simply be
re-evaluated. A `regraft` step substituted the new src store path into
the baked derivation and re-derived it canonically with
`builtins.derivation`, reproducing the baked drvPath bit-for-bit when the
source was unchanged.

## What it bought

Smaller blobs, proportional to how much of the seed was *source* rather
than dependency outputs:

| | sources | drvs |
|---|---|---|
| hello | 118 MB | 65 MB |
| cpp-boost | 253 MB | 205 MB |
| python | 728 MB | 683 MB |
| rust-ripgrep | 694 MB | 646 MB |

And it removed evaluation from the consumer's build. On the example set
that was worth nothing: six of seven examples benchmarked within noise
of sources mode, because their flakes evaluate in 1-4s while a
deliberately non-substitutable compile dominates. The one example built
to isolate evaluation (`examples/eval-heavy`) showed the real effect --
the nix-seed action step fell from 9.6s to 2.8s on a 2-core x86 runner
(-71%), and 6.4s to 3.6s on arm.

## Why it was removed

The saving is proportional to evaluation, and evaluation cost varies by
an order of magnitude across real projects. Measured warm, eval cache
off, on one fast desktop core (CPU time is the better predictor of a
2-core runner):

| project | wall | cpu | IFD |
|---|---|---|---|
| nixvim (`docs`) | 22.1s | 17.9s | no |
| devenv | 11.7s | 10.3s | yes |
| hercules-ci-agent | 6.6s | 3.2s | yes |
| cachix | 4.1s | 2.6s | yes |
| lanzaboote (`lzbt`) | 3.3s | 2.1s | no |

So the variant paid for itself on module-heavy and IFD-heavy consumers
and did nothing for ordinary ones -- while costing, permanently: a
second seed built and pushed per example per arch, a second lock file, a
second set of workflows, and every future change having to work in both
modes. The graft could not be dropped to keep the cheap half, either:
without it a drvs seed rebuilds the *old* source on every commit, so the
variant's value and its most delicate component were the same thing.

Set against a benefit only some consumers can use, that was not a trade
worth carrying in a tool other projects adopt.

## What was kept

- `examples/eval-heavy`, which measures the evaluation floor every
  consumer pays.
- `bin/build`'s attribute selector (`bin/build DIR [ATTR]`), which came
  out of making non-default outputs addressable and is useful on its own.
- The seed attribute -> image/lock naming in `bin/build-seed`, which is
  generic rather than variant-specific.

## If it is ever revived

Three things were known to be missing or fragile:

1. `regraft` parsed `nix derivation show`'s JSON, whose schema moved at
   v3 -> v4 during development. It ended up asserting the version and
   failing loudly, which is the minimum bar.
2. The graft swapped `src` only. Anything evaluation derived from source
   *content* stayed frozen -- crane's vendor drv, pyproject-nix's
   rendered dependency set -- so editing `Cargo.toml` rather than a
   `.rs` file built against a stale dependency set, silently. This was
   documented rather than enforced.
3. The intended guard was never built: seed both variants and assert the
   grafted drv equals what a sources-mode evaluation produces for the
   same checkout, turning the envelope from a promise into a test.
