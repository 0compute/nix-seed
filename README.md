# Nix Seed

Nix Seed drastically speeds up CI[^ci] for Nix-based projects on non-native
ephemeral runners. Instead of downloading/compiling the project's dependencies
on every run, it packages them into a reusable container.

*Under the hood:* It creates OCI seed images with the dependency graph packaged
as content-addressed layers, eliminating the need to reconstruct the
`/nix/store` on ephemeral runners.

Build provenance is cryptographically attested: quorum proves that what is in
git is what was built.

For full implementation detail, see [design](./DESIGN.md).

## Why?

In environments without a pre-populated `/nix/store` (i.e. standard GitHub
Actions runners), every dependency, and the dependency's dependencies, must be
downloaded or built before the actual build can begin. This setup tax often
dominates total job time.

Build time does not change. Setup time does. Source must always be fetched
(typically via shallow clone).

Traditional CI setup scales with total dependency size. Seeded CI setup scales
with dependency change since the last seed.

When only application code changes, the previous seed is reused and
time-to-build is near-instant. When a dependency changes, or when no seed exists
yet, the seed is built before application build.

## Quickstart

> [!NOTE] This quickstart demonstrates a minimal, single-builder (1-of-1)
> example for evaluation. This completely bypasses the trust model. For
> production, see the [Production Setup](#production-setup) section.

Add `nix-seed` to your flake and expose a `seed` attribute:

```nix
{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = "github:0compute/nix-seed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs: {
    packages =
      inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          # placeholder: replace with your derivation
          default = pkgs.hello;
          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };
        }
      );
  };

}
```

### GitHub Actions

Add a workflow:

> [!WARNING] This job runs with `packages: write` and `id-token: write`
> permissions. Never trigger seed generation with write tokens on untrusted pull
> requests to prevent privilege escalation and/or namespace poisoning.

```yaml
on:
  push:
    branches:
      - master

jobs:
  seed:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
      packages: write
    steps:
      - uses: actions/checkout@v6
      - uses: 0compute/nix-seed@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
  build:
    runs-on: ubuntu-latest
    needs: seed
    steps:
      - uses: actions/checkout@v6
      - uses: 0compute/nix-seed@v1/actions/build
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

______________________________________________________________________

## Production Setup

*This section is a stub.* For a production deployment, you must configure an N-of-M builder quorum spanning independent failure domains. Documentation on configuring `modules/builders.nix`, secret management (HSMs vs. CI variables), and executing the genesis ceremony will go here.

## Troubleshooting

*This section is a stub.* Future content will cover:
- How to shell into a seed container to debug environment issues.
- Distinguishing between Nix evaluation errors and seed orchestration failures.
- Checking L2 quorum status and diagnosing missing attestations.

______________________________________________________________________

## Footnotes

\[^ci\]: **CI** - Continuous Integration. The practice of automating the
integration of code changes from multiple contributors into a single software
project.
