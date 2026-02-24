# Nix Seed

> Trusting trust is a bug. Nix Seed is the patch.

Nix Seed provides high-performance/high-integrity containerized Nix build environments.

| Line Item                         | Cost      |
| ---                               | ---       |
| 🧘 **Recovered Engineering Flow** | -$$$      |
| ☁️ **Reclaimed Build Minutes**    | -$$$      |
| 🔐 **Supply Chain Integrity**     | Priceless |

## Problem: Purity Ain't Free

Nix is not well suited to non-native ephemeral environments. CI runners must install
Nix, then realize the closure, either substituting from binary cache or building from
source. This burns Network/CPU.

For GitHub CI, [Cache Nix Action](https://github.com/nix-community/cache-nix-action) and
[Nix Magic Cache](https://github.com/DeterminateSystems/magic-nix-cache-action) reduce
the need to reach outside of GitHub's backbone, but are still largely network and CPU
bound.

## Solution: Seed Containers

Baking the closure into layered OCI containers eliminates build-time dependency
realization. Commits affecting only application code trigger near-instant builds as
cached layers are reused.

GHCR hosting ensures high-speed pulls and minimal cold-start latency for GitHub runners.

## Problem: Trusting Trust

> The source was clean, the build hermetic, but the compiler was pwned.

Even with hermetic and deterministic builds, attacks like Ken Thompson's
[Trusting Trust](https://dl.acm.org/doi/10.1145/358198.358210) remain a concern. A
rigged build environment that undetectably injects code during compilation is always a
possibility.

## Solution: Trust No Fucker

1. Post build, generate a JSON predicate containing:

- commit: git sha
- system: `stdenv.hostPlatform.system` i.e. `x86_64-linux` or `aarch64-darwin`
- narHash: nar hash of the built image
- builder identity: who performed the build

1. Sign the predicate and pushes to the registry as an OCI artifact attached to the
   image, then log it to [Rekor](https://rekor.dev/).

1. Promotion is gated by an n-of-m quorum of Rekor entries.

See [publish](./bin/publish) for full detail.

### Endgame (TODO)

An n-of-m quorum still relies on a centralized actor (like GitHub Actions) to enforce
the gate and update registry tags. The endgame moves this from a "log" to a **truth
machine** by anchoring a Merkle root of all system attestations to an Ethereum L2 (e.g.,
Base or Arbitrum).

This adds three critical layers of security:

1. **Immutable Settlement:** The root of trust moves from a CI script to on-chain logic.
   "Promotion" isn't a mutable registry tag; it's an immutable state change in a smart
   contract.
1. **Atomic Verification:** While Rekor holds individual multi-system entries, the L2
   aggregates them into a single cryptographic commitment. You verify one root to trust
   the entire cross-platform release.
1. **Registry-Agnostic Proof:** Users and production clusters verify images directly
   against the L2 contract. You don't have to trust that the registry is serving the
   correct image or the correct tags.

## GitHub Action Integration

Nix Seed provides a [GitHub Action](./action.yml) to build seed containers.

## License Compliance

Nix Seed is unimpeachable. Upstream license terms for non-redistributable SDKs are fully
respected, leaving zero surface area for litigation.
