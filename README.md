# Nix Seed

Nix Seed produces OCI seed images for Nix-built projects, packaging their
dependency closure as content-addressed OCI layers to eliminate per-job
reconstruction of `/nix/store`.

The design goal is CI setup time. Because the images are content-addressed
outputs of reproducible Nix builds rooted at an auditable bootstrap chain,
supply-chain trust properties come without additional work. See
[DESIGN.md](DESIGN.md) for architecture, performance model, trust modes, and
threat model.

## Why

In environments without a pre-populated `/nix/store`, the entire dependency
closure must be realized before a build can begin. This setup tax often
dominates total job time.

Build time does not change. Setup time does. Source must always be fetched
(typically via shallow clone).

Traditional CI setup scales with total dependency size. Seeded CI setup scales
with dependency change since the last seed.

When only application code changes, the previous seed is reused and
time-to-build is near-instant. When the input graph changes, or when no seed
exists yet, the seed is built before application build.

## Quickstart

Add `nix-seed` to your flake and expose a `seed` attribute:

```nix
{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = "github:your-org/nix-seed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs: {

    seedCfg = {
        builders = {
        aws = { ... };
        azure = { ... };
        gcp = { ... };
        github = { ... };
        gitlab = { ... };
        };
        # allow 1 builder to be down
        quorum = 4;
    };

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

```yaml
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
    container: ghcr.io/${{ github.repository }}-seed:${{ hashFiles('flake.lock') }}
    steps:
      - uses: actions/checkout@v6
      - uses: 0compute/nix-seed@v1/actions/build.yaml
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```
