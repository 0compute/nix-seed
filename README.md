# Nix Seed

Nix Seed drastically speeds up builds for Nix-based projects on non-native
ephemeral CI runners. Instead of downloading/compiling the project's dependencies
on every run, it packages them into a reusable container.

*Under the hood:* It creates OCI seed images with the dependency closure
packaged as content-addressed layers, eliminating the need to reconstruct the
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

## Production Setup

*This section is a stub.* Production mode anchors releases on Ethereum L2 using
an N-of-M builder quorum. See [Design: Production](./DESIGN.md#production-todo)
for the full trust model.

**Setup sequence:**

1. **Configure builders** — define your builder set in `modules/builders.nix`
   with distinct `corporateParent`, `jurisdiction`, and signing keys. N ≥ 3,
   each on independent infrastructure and CI provider.
2. **Execute genesis** — all M builders independently build the seed from source
   with substituters disabled, submit unanimous attestations, and co-sign the
   genesis transaction. See [Design: Genesis](./DESIGN.md#genesis).
3. **Key management** — store builder signing keys in HSMs, not CI environment
   variables. Configure governance multi-sig for key rotation and revocation.
4. **Verify independence** — no two quorum builders may share a corporate parent,
   CI provider, or OIDC issuer.

See [Design: Threat Actors](./DESIGN.md#threat-actors) for jurisdiction guidance
on selecting independent builder operators.

## Troubleshooting

*This section is a stub.* Future content will cover:

- How to shell into a seed container to debug environment issues.
- Distinguishing between Nix evaluation errors and seed orchestration failures.
- Checking L2 quorum status and diagnosing missing attestations.
