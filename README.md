# Nix Seed

Nix Seed provides high-performance, high-integrity, multi-system containerized
Nix build environments.

## Problem: Purity Ain't Free

Nix is poorly suited to non-native CI environments. Before a build can start,
Nix must be installed and the input graph realized - substituting from cache or
building as required. Binary caches are not local; fetching and unpacking is
network/compute bound. For GitHub CI,
[Cache Nix Action](https://github.com/nix-community/cache-nix-action) and
[Nix Magic Cache](https://github.com/DeterminateSystems/magic-nix-cache-action)
trade public-internet fetches for GHA cache fetch and unpack, but remain
network/compute bound.

## Solution: Seed Containers

Seed containers pre-realize inputs as OCI layers, making them extremely
cacheable. Co-locating the CI runners and registry ensures minimal cold-start
latency.

When only application code changes, a seed from the last input change is
available, making time-to-build near-instant.

When the input graph changes, seed build runs before app build. Time-to-build
depends on what changed, where in the graph, whether it is available from a
binary cache, etc.

<!-- FIXME: why no matching tag? -->

After building itself, the seed updates `seed-self`, a self-referencing flake
input, so app builds know which seed tag to use. If no seed exists (first build,
or when `seed-self` has no matching tag), the build falls back to a seedless
run.

## Problem: Trusting Trust

> The source was clean, the build hermetic, but the compiler was pwned.

Even with hermetic and deterministic builds, Ken Thompson's
[Trusting Trust](https://dl.acm.org/doi/10.1145/358198.358210) attack remains a
concern. A subverted build environment that undetectably injects code at compile
time is always possible.

## Solution: Trust No Fucker

After build, the seed generates an [SLSA provenance](https://slsa.dev)
predicate, attests it with
[`cosign attest`](https://github.com/sigstore/cosign), and logs to
[Rekor](https://github.com/sigstore/rekor). Seed images are verified against
Rekor before each app build, extending coverage to the build environment itself.

Promotion is gated by a quorum of Rekor entries: `n`-of-`m` or `m`-of-`m`,
configured via `seedCfg.rekor.quorum`. The quorum is meaningful only if builders
are legally, geographically, and technically separate - an attacker must subvert
`n` or more independent systems to forge a promotion:

<!-- AGENT: what about Commercially? -->

- **Legally:** distinct jurisdictions and organizational control cannot all be
  coerced or subpoenaed simultaneously.
- **Geographically:** physical separation across regions prevents coordinated
  seizure or outage.
- **Technically:** different cloud providers and hardware prevent a single
  infrastructure compromise from affecting all signers.

Two quorum modes are supported:

- **`n`-of-`m`:** up to (`m`-`n`) builders can fail or go offline without
  blocking promotion. An attacker must subvert `n` builders to forge a
  promotion.
- **`m`-of-`m` (unanimous):** strongest security guarantee - all builders must
  agree. A single builder going offline blocks promotion.

The designated master builder (`seedCfg.builders.<name>.master = true`) runs the
promoter. It queries Rekor for entries whose subject matches the image digest -
since builds are reproducible, all independent builders attest the same digest.
Builder identity uses OIDC keyless signing: each platform's OIDC token acts as
the signing identity (`https://token.actions.githubusercontent.com` for GHA,
`https://gitlab.com` for GitLab), eliminating private key management. The
promoter waits up to `seedCfg.rekor.deadline` for quorum before failing the
build.

> [!WARNING] [Reproducible builds](https://reproducible-builds.org/) are a
> prerequisite. Independent builders must produce bit-for-bit identical outputs
> from the same inputs. Without reproducibility, a quorum cannot distinguish a
> legitimate build from a subverted one.

### Endgame (TODO)

Currently, quorum enforcement relies on a centralized actor (such as GitHub
Actions) to gate promotion and update registry tags. Endgame moves this from a
"log" to a **truth machine** by anchoring a Merkle root of all system
attestations to an Ethereum L2 (e.g. [Arbitrum](https://arbitrum.io) or
[Base](https://base.org)).

This adds three critical layers of security:

1. **Immutable Settlement:** Trust moves from a CI script to on-chain logic.
   "Promotion" isn't a mutable registry tag; it's an immutable state change in a
   smart contract.
1. **Atomic Verification:** While [Rekor](https://github.com/sigstore/rekor)
   holds individual multi-system entries, the L2 aggregates them into a single
   cryptographic commitment. One root verifies the entire cross-platform
   release.
1. **Registry-Agnostic Proof:** Users and production clusters verify images
   directly against the L2 contract. The registry cannot serve a tampered image
   or tag undetected.

This approach effectively solves the **"Who watches the watchers?"** problem by
ensuring that even if a registry or a master builder is compromised, they cannot
forge a "promoted" status without the cryptographic consent of the quorum,
verified by a decentralized L2.

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
    packages =
      (inputs.nixpkgs.lib.genAttrs (import inputs.systems) (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
        in
        {
          # placeholder: replace with your package
          default = pkgs.hello;
          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };
        }
      ))
      # optional: TNF config
      // {
        seedCfg = {
          builders = {
            aws = { };
            azure = { };
            gcp = { };
            github.master = true;
            gitlab = { };
          };
          rekor.quorum = 4;
        };
      };
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

______________________________________________________________________

If the build result is a container, it is pushed to the registry. The provenance
attestation is attached to the image as an OCI artifact.

### GHCR

GHCR is co-located with GHA runners, minimizing registry fetch latency. The seed
is tagged by the `flake.lock` hash: if inputs have not changed since the last
seed build, the existing image is reused without a rebuild. The registry
defaults to `ghcr.io` and can be changed via `seedCfg.registry`.

## Compliance

Upstream license terms for non-redistributable SDKs are fully respected.
