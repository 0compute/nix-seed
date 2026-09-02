# TODO

- must use signed commits
- look at `dive`
- `.seed.lock` has no `kind` discriminator. DESIGN.md#building-from-seed
  documents `version` and `kind` and argues they must exist *before* a second
  delivery mechanism does, because every consumer commits the lock and adding a
  field later is a migration across all of them. The real schema
  (`bin/build-seed`, `update_lock`) is a flat `{repository, tag, systems}`.
  Worth doing first if macOS support (DESIGN.md#macos) is ever started.
- examples have no `isLinux` guard. `modules/packages.nix` guards nix-seed's own
  outputs so the flake still evaluates on a Mac, but each `examples/*/flake.nix`
  exposes `seed` across `lib.systems.flakeExposed`, so
  `packages.aarch64-darwin.seed` throws if forced. A contributor on a Mac hits
  this today.
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
