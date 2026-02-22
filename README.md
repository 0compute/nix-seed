# Nix Seed

Hermetic. Cacheable. Fast.

## Overview

`Nix Seed` provides Nix OCI seeds for build and runtime environments. It pins all
inputs for deterministic, cacheable builds, so rebuilds are quick when layers are
unchanged.

![XKCD Compiling](https://imgs.xkcd.com/comics/compiling.png)

> > Not any more fuckers. Work Harder.

**By using pre-baked OCI layers, Nix Seed targets fast rebuilds when cached without
compromising hermeticity or reproducibility.** Hermetic builds isolate from host and
network influences; reproducible builds aim for identical outputs when inputs and
tooling are pinned.

- **Build seeds:** hermetic, full-featured; include base, library, apps, checks,
  devShells, overlays.
- **Runtime seeds:** hermetic and slim; include base, library, and apps. Optional musl
  variant is available for smaller runtimes.

**Note:** Base layers use a minimized Nixpkgs derivation. Size depends on the package
set but remains fully Nix-native.

## Quick Start

Build the default seed and load it into Docker:

```sh
nix build .#seed
docker load < result
```

List loaded images:

```sh
docker image list
```

## Extreme Cacheability and Baked Flakes

**Extreme cacheability** is a core principle. Inputs are baked into the local store and
distributed via caches, so pre-built layers can be reused across developers, CI, and
registries.

### Comparison with Nix Community / GH Actions Caches

| Feature | Nix Seed (pre-baked layers) | Standard caches | | --- | --- | --- | |
Hermetic build | ✅ fully isolated | ⚠ may fetch missing paths | | Reproducible | ✅
pinned inputs/tools | ⚠ host/tool differences | | Incremental rebuilds | ✅ only changed
layers | ⚠ larger rebuild surface | | Multi-layer reuse | ✅ base, libs, apps, checks,
devShells, overlays | ❌ flat cache | | Cache keys | ✅ flake input hash per layer | ⚠ ad
hoc or per-derivation | | Network dependency | ❌ offline possible | ⚠ remote caches;
bandwidth + untar CPU | | Developer speed | ✅ near-instant when cached | ⚠ slower; more
network and CPU |

**Summary:** Nix Seed turns the pinned dependency graph into reusable OCI layers, not
single store paths. That yields faster, hermetic, reproducible builds, without the setup
tax of repeatedly populating per-run Nix caches in typical GitHub Actions flows.

## Layer -> OCI -> Cache Diagram

Split output/layer to OCI layer to cache key mapping:

| Output or layer | OCI layer | Cache key | | --- | --- | --- | | base | Layer 1 |
hash(base + inputs) | | library | Layer 2 | hash(library + inputs) | | apps | Layer 3 |
hash(apps + scripts) | | checks | Layer 4 | hash(tests + deps) | | devShells | Layer 5 |
hash(dev tools + notebooks) | | overlays | Layer 6 | hash(overlays) |

- Runtime seed: base + library + apps.
- Build seed: all layers for hermetic, cacheable builds.

## Flake Schema Layered Nix OCI Seeds

Nix Seed supports split outputs per derivation to implement layers automatically. Users
can define dependencies in standard layer names, and Nix Seed will produce hermetic,
cacheable layers.

Usage outline:

- Define split outputs for `base`, `library`, `apps`, optional `checks`, `devShells`,
  `overlays`.
- Keep each output scoped to its layer dependencies.
- Runtime images include base + library + apps; build images include all layers.

### Standard Layer Helper Function (Embedded)

```nix
{ pkgs }:

let
  standardLayers = {
    base = [ pkgs.python pkgs.gcc pkgs.coreutils ];
    library = [ pkgs.numpy pkgs.pandas pkgs.matplotlib ];
    apps = [ ./my-script ./my-model ];
    checks = [ ./tests ];
    devShells = [ pkgs.jupyter pkgs.streamlit ];
    overlays = [ ./my-overlay ];
  };

in
  pkgs.stdenv.mkDerivation {
    name = "nix-seed-standard-layers";
    outputs = builtins.attrNames standardLayers;

    buildCommand = ''
      for layer in ${builtins.concatStringsSep " " (builtins.attrNames standardLayers)}; do
        mkdir -p $out/$layer
        cp -r ${standardLayers.$layer}/* $out/$layer/
      done
    '';
  }
```

Users can override or extend standard layers as needed. Each split output maps to an OCI
layer. Runtime seeds include base + library + apps; build seeds include all layers.
Runtime excludes: checks, devShells, overlays.

## Layered Seed Architecture

- **Base layer:** OS, compilers, Python runtime (minimal Nixpkgs).
- **Library layer:** libraries, numerical and ML packages.
- **Apps layer:** Python scripts, AI pipelines, models.
- **Checks layer:** unit tests, validation scripts.
- **DevShells layer:** developer tools, Jupyter, Streamlit (build-only).
- **Overlays layer:** patches, version overrides (build-only).

## Runtime vs Build Layer Table

| Layer | Runtime seed | Build seed | | --- | --- | --- | | base | ✅ | ✅ | | library
| ✅ | ✅ | | apps | ✅ | ✅ | | checks | ❌ | ✅ | | devShells | ❌ | ✅ | | overlays | ❌ | ✅ |

Runtime includes only base + library + apps. Optional musl runtime is available for
smaller images. Build seed includes all inputs for all layers to preserve hermeticity
and caching.

Expected runtime sizes:

- Small scripts: ~1-10 MB.
- Minimal base: ~15-25 MB.
- AI stack runtime: ~500-900 MB (CPU), GPU variant ~2-3 GB compressed.

## GitHub Actions Integration

Nix Seed can be used in [GitHub Actions](https://docs.github.com/actions) to build and
publish images with pinned inputs and cacheable layers.

- Run builds with `--option substitute false` to force local derivation builds.
- If your workflow uses Node-based actions, ensure Node is available in the build image
  at a predictable path.
- Setting `github_token` triggers load, tag, and push in one publish step. Omit it to
  build only. Add extra tags via `tags`. Use `registry` to push somewhere other than
  ghcr.io. Use `tag_latest: true` only when publishing the manifest after all systems
  finish. `seed_attr` defaults to `.#seed`. Seeds default to `substitutes = false`;
  set `substitutes = true` in `mkseed.nix` if you want to allow binary cache use inside
  the seed.

Example workflow using the local composite action:

```yaml
name: build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: ./
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          seed_attr: .#seed
```

Example workflow using a published action (replace the ref):

```yaml
name: build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: your-org/nix-seed@v0
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          seed_attr: .#seed
```

## Expected Time-to-Build

| Scenario | Approx. time | Notes | | --- | --- | --- | | Fully cached | ~0-5 sec | Eval
\+ layer verification | | Project layer invalidated | 10-60 sec | Top-level package
rebuild | | Library layer invalidated | 1-5 min | Dependency rebuild | | Toolchain/base
invalidated | 5-20+ min | Full graph rebuild |

Incremental rebuilds only invalidate layers whose inputs changed. Runtime seeds are
hermetic and slim; build seeds include all inputs for all layers.

## Multi-Target / Multi-Arch

- Cross-compilation handled hermetically.
- Supports x86_64 and ARM64, Linux and Darwin targets.
- Darwin builds run inside Linux OCI seeds on macOS hosts.
- SDKs for macOS are build-time-only; where required, only the flake hash is used.
- No emulation required for CPU-only builds.
- Optional musl runtimes available for smaller images.
- Designed for developer speed: only changed layers rebuild.
- Nix `system` is the platform triple used by flake outputs (for example,
  `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`). OCI manifests use `os/arch`
  (`linux/amd64`, `linux/arm64`, `darwin/arm64`); pick the matching Nix `system` when
  building per-arch images and apply `latest` only when tagging the manifest list.

## Trust No Fucker

Even with fully reproducible builds, attacks like Ken Thompson's
[Trusting Trust](https://dl.acm.org/doi/10.1145/358198.358210) remain a concern. A
malicious compiler could inject code during compilation without being visible in source
code.

To guarantee hermetic, reproducible, and verifiable builds, Nix Seed produces a build
attestation for every seed:

```json
{
  "flakeHash": "sha256-flake-inputs",
  "layerHashes": {
    "base": "sha256",
    "library": "sha256",
    "apps": "sha256",
    "checks": "sha256",
    "devShells": "sha256",
    "overlays": "sha256"
  },
  "seedDigest": "sha256",
  "signature": "gpg-or-slsa",
  "builtBy": "builder-identity",
  "timestamp": "ISO8601"
}
```

- `flakeHash`: inputs match the declared pinned flake.
- `layerHashes`: each split output layer is unmodified.
- `seedDigest`: final OCI image digest.
- `signature`: optional GPG or SLSA signature for authenticity.

Attestations can be stored as JSON files or OCI annotations, allowing developers and
CI/CD pipelines to verify builds independently.

For multi-builder assurance, require an n-of-m threshold of independent attestations
over the same build hash and store the bundle in a transparency log (for example, Rekor
or a self-hosted equivalent). Verification should check the quorum, not a single signer.
If stronger coordination is needed, run a small permissioned consensus log (for example,
Tendermint or HotStuff validators) to anchor attestation entries without public-chain
overhead.

Use [`bin/verify`](./bin/verify) for quorum verification and optional OCI attachment via
`oras` (args: IMAGE_REF [-d ATTESTATIONS_DIR] [-r REQUIRED_ATTESTATIONS] [-A] [-a]
[--dry-run]).

CI pattern to verify quorum and attach (example):

```yaml
jobs:
  attest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Fetch attestations
        run: |
          mkdir -p attestations
          aws s3 cp s3://your-bucket/$GITHUB_SHA/ attestations/ --recursive
      - name: Verify n-of-m and attach
        run: |
          ./bin/verify \
            ghcr.io/${{ github.repository }}:${{ github.sha }} \
            -d attestations \
            -r 2 \
            -A \
            -a
```

Use `--dry-run` with `./bin/verify` to verify without attaching.

Note: [`mkseed.nix`](./mkseed.nix) prepends `${./bin}` to PATH inside seeds so
helpers like [`bin/verify`](./bin/verify) are available in built images.

Multi-arch: attach per-arch attestations before composing a manifest list so each
platform entry carries its own attestation; consumers pull the manifest, and runtimes
fetch the matching platform layers automatically.

Flake package `verify` (resholve via `writeShellApplication`) is available with
`nix build .#verify` for pinned, dependency-resolved usage.

For highest assurance, combine n-of-m attestations with a full-source bootstrap chain
for compilers and critical tools, then cross-verify hashes from independent builders
before promotion.

Full-source bootstraps are achievable but non-trivial: see Guix and bootstrappable
builds (mes, stage0, tinycc) for minimal binary seeds and documented compiler chains.
Expect extra effort to align toolchains, trim seeds, and verify each stage across
independent builders.

### Zero-Trust Attestation Flow

To keep Trust No Fucker actionable we require independent builders, transparent attestations,
and immutable promotion anchors.

- **Nix:** Each builder runs inside an OCI seed with a pinned `flake.lock`, then reads the
  per-system `narHash` via `nix path-info --json .#target`.
- **Sigstore:** Builders issue In-Toto statements with `cosign` using allowed OIDC subjects
  and record `{commit, system, narHash}` in Rekor.
- **Blockchain (EVM L2):** Once $n$ of $m$ builders agree, an authorized caller records
  `commit+system -> narHash` in the smart contract, batching entries with a Merkle root for
  gas efficiency.

Flow:
1. Hermetic builders capture deterministic hashes.
2. Each builder logs a Sigstore attestation to Rekor.
3. A watchdog polls Rekor, verifies identities, and declares quorum when $n$ hashes match.
4. Upon quorum the watchdog (or a multisig) calls the L2 contract to anchor the promotion.

Next steps:
1. Ship the Nix tooling (builder helpers, Sigstore wrapper, Rekor poller, watchdog, contract
   caller) with Bats/Nix coverage.
2. Make the policy explicit (`n`, `m`, Rekor URL, permitted issuers/subjects, target L2
   + contract ABI).
3. Hook the workflow into CI/flake checks so promotions run only after every stage passes.

### Legal Compliance

- Apple SDKs are strictly build-time dependencies; no SDK binaries are included in build
  or runtime seeds.
- macOS-targeted builds must execute on licensed macOS hosts or runners.
- Runtime seeds include only Nix-native dependencies and built outputs, never Apple
  SDK content.
- All Nixpkgs, overlays, and other open-source inputs are fully redistributable.
