# Nix Seed

Nix Seed produces OCI seed images for Nix-built projects, packaging their dependency closure as content-addressed OCI layers to eliminate per-job reconstruction of `/nix/store`.

## Why

In environments without a pre-populated `/nix/store`, the entire dependency closure must be realized before a build can begin. For Nix-built projects, this setup phase can dominate total job time.

Nix Seed removes closure realization from the critical path.

Build time does not change.
Setup time does.

Source must always be fetched (typically via a shallow clone). Seeded CI does not change that constant cost.

Traditional CI setup scales with total dependency size.
Seeded CI setup scales with dependency change since the last seed.

---

# Release Model

OCI seed images are addressed by digest only. Registry tags and metadata are non-authoritative.

Tags are applied for operational convenience — to locate an image for a given `flake.lock`, to mark a promoted image — but they carry no semantic weight. The digest is the identity.

A seed image is built once per unique closure. If `flake.lock` has not changed, the closure has not changed, and the existing image is reused without rebuild.

Seed images are not versioned. They are not released. They are either current or they are not.

---

# Architecture

## Seed Construction

A seed is an OCI layered image produced by `lib.mkSeed`. It captures the full Nix dependency closure required to build a project's packages, checks, and apps.

The image is constructed by `dockerTools.buildLayeredImage`, which decomposes the closure into discrete OCI layers. Each layer corresponds to one or more Nix store paths. Because store paths are content-addressed, layers are stable across rebuilds of equivalent closures.

`mkseed.nix` accepts:

- `pkgs` — nixpkgs instance
- `self` — the project flake
- `name` — image name
- `nix` — Nix derivation to include
- `nixConf` — Nix configuration to embed
- `substitutes` — binary cache substituters
- `debugTools` — optional debugging utilities
- `contents` — additional store paths to include

The image includes `/tmp` (required by Nix builds), a compatible Node.js installation for GitHub Actions runner compatibility, and glibc at the multiarch path expected by the Actions runtime. `NIX_CONFIG`, `SSL_CERT_FILE`, `LD_LIBRARY_PATH`, and `PATH` are set at image build time.

## Layer Reuse

OCI layer reuse is the mechanism that makes seeded CI fast. When a seed image is pulled, the container runtime fetches only layers absent from its local cache. If `flake.lock` has not changed since the last pull, no layers need to be fetched at all.

This is not cache warming. It is structural reuse: the same store paths produce the same layers, always.

## Self-Reference

A seed image does not know its own digest at build time. The solution is a `seed-self` flake input that is updated after publish. Subsequent builds read `seed-self` to determine which seed to pull.

This creates a well-defined contract: the flake declares its seed. The seed is pinned in `flake.lock`. CI pulls the pinned seed.

If no seed exists for the current `flake.lock`, builds fall back to a seedless run.

---

# CI Integration

## GitHub Actions

The `action.yml` GitHub Action wraps the full seed lifecycle:

1. Install Nix
2. Optionally configure Cachix
3. Build the seed image via `nix build`
4. Publish to a registry (default: GHCR)

The seed is tagged with the SHA of `flake.lock` for addressability and with the commit SHA for traceability. The tag is a pointer; the digest is the identity.

## Multi-Provider Builds

Seed images are built by a primary builder (typically GitHub) and optionally verified by independent builders on other providers. `bin/trigger-ci` dispatches builds to GitLab, CircleCI, and AppVeyor using their respective pipeline APIs. `bin/sync-ci-envs` propagates required environment variables (registry credentials, signing keys, OIDC configuration) across providers.

---

# Attestation and Verification

## SLSA Provenance

After publish, `bin/publish` generates a SLSA provenance predicate containing:

- The image digest
- The builder identity (OIDC subject)
- The build timestamp
- The source repository and commit

The predicate is signed with `cosign attest` using OIDC keyless signing. No private key is managed. The builder's identity is its OIDC token, issued by the platform (`token.actions.githubusercontent.com` for GitHub Actions).

All attestations are logged to Rekor, a public append-only transparency log.

## Quorum Verification

`bin/verify` implements N-of-M quorum verification. It queries Rekor for attestations matching the image digest and verifies that at least N independent builders — from M configured — have attested the same digest.

A single compromised builder cannot promote a seed. A quorum of independent attestations is required.

Builders must be:

- Legally separate (different organizations or jurisdictions)
- Technically separate (different cloud providers, hardware, or runtime environments)
- Reproducible (bit-for-bit identical outputs, verified by digest agreement)

The quorum threshold is configurable. The default is 3-of-M.

Once the quorum is satisfied, `bin/verify` attaches the attestation bundle to the image via `oras` and optionally annotates it with `skopeo`.

---

# Provider Configuration

`modules/seedcfg.nix` documents the operational characteristics of supported CI providers: Alibaba Cloud, AppVeyor, AWS CodeBuild, Azure Pipelines, Bitbucket Pipelines, CircleCI, GitLab CI, and GitHub Actions.

For each provider it records:

- Cloud provider and sovereignty jurisdiction
- OIDC support and issuer URL
- KMS availability
- Free tier availability
- Runner hardware (CPU architecture, OS, memory, storage, virtualization type)

This is reference data for configuring independent builder sets. Effective quorum requires builders from providers in different legal jurisdictions and under different administrative control.

---

# Tooling

## nix-path-mermaid

`nix-path-mermaid` is a CLI tool that generates Mermaid dependency graphs for Nix store paths. It is useful for visualizing closure structure and identifying unexpectedly large dependencies.

Nodes are color-coded by closure size using quantile thresholds:

- Green: below median
- Yellow: above median
- Red: above 75th percentile

## Examples

`/examples` contains seed configurations for three language ecosystems:

- **python** — ML build environment using pyproject.nix
- **rust-app** — Rust project with Cargo dependencies
- **cpp-boost** — C++ project with Boost, built with CMake

Each example includes a complete flake with `mkSeed` configuration and a corresponding GitHub Actions workflow.

---

# Non-Goals

Nix Seed does not:

- Change build time. Only setup time is affected.
- Replace binary caches. Seeds and substituters are complementary.
- Manage source fetching. Shallow clones remain a constant-cost step outside the seed.
- Provide runtime containers. Seeds are build-time infrastructure, not deployment artifacts.
