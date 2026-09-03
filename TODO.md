# TODO

- must use signed commits
- look at `dive`
- `.seed.lock` still has no `version`, and DESIGN.md#building-from-seed
  documents one. `kind` turned out unnecessary when the second delivery
  mechanism landed: the system key already says which artefact a digest is
  for (`*-linux` squashfs, `*-darwin` dmg). `version` is the part with no
  substitute, and adding it later is a migration across every consumer's
  committed lock.
- examples enumerate `lib.systems.flakeExposed`, which is wider than the
  systems `mkSeed` supports, so `packages.armv7l-linux.seed` and friends throw
  if forced. Harmless while CI only forces the three real ones; a contributor
  running `nix flake check` on an example may not agree.
- post build the seed updates flake.nix with its commit. Why? so the app build
  can call the right container, ouroboros the seed build is a self-reference in
  the flake

## Flake Parts

- use hercules-ci for promotion, hercules-ci-effects
- review devshell, make-shell
- https://flake.parts/options/mission-control.html
- rust/cargo
- https://flake.parts/options/nix-oci.html
- https://flake.parts/options/pydev.html
- https://github.com/divnix/std

## Funding

- Sovereign Tech Fund
- NLnet Foundation
