# Nix Seed

Fast, trustable, Nix builds on non-native ephemeral CI.

> Woosh... Wondering what that even means? See [Glossary](./GLOSSARY.md).

Happy-path builds - application code change, dependencies unchanged - start
*building* near-instantly. The dependency closure ships pre-built as an OCI
image; pull, mount, build.

CI providers with co-located registries, like GitHub and GHCR, mean the pull is
fast. The extreme cacheability of Nix-built OCI layers means that the pull may
not be necessary in the first place.

> Flow state, unbroken: $$$
>
> Compute bill, slashed: $$$
>
> A build you can trust: Priceless

See [design](./DESIGN.md) for full detail.

## Why?

Standard CI runners rebuild every Nix dependency from scratch. For a typical
project: 60-90 seconds of setup per job.

Build time does not change. Setup time is virtually eliminated.

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

Production mode anchors releases on Ethereum L2 using an N-of-M builder quorum.
No single builder, organisation, or jurisdiction can unilaterally forge a
release. See [Design: Production](./DESIGN.md#production-todo) for the full
trust model.

> [!WARNING]
>
> The [design doc](./DESIGN.md) contains critical security information.
>
> Read it. Twice. Or, get pwned.

**Setup sequence:**

1. **Configure builders** - define your builder set in `modules/builders.nix`
   with distinct `corporateParent`, `jurisdiction`, and signing keys. N >= 3,
   each on independent infrastructure and CI provider.
2. **Execute genesis** - all M builders independently build the seed from source
   with substituters disabled, submit unanimous attestations, and co-sign the
   genesis transaction. See [Design: Genesis](./DESIGN.md#genesis).
3. **Key management** - store builder signing keys in HSMs, not CI environment
   variables. Configure governance multi-sig for key rotation and revocation.
4. **Verify independence** - no two quorum builders may share a corporate parent,
   CI provider, or OIDC issuer.

See [Design: Threat Actors](./DESIGN.md#threat-actors) for guidance on selecting
independent builder operators.
