# Nix Seed

Traditional cache-backed Nix on non-native ephemeral CI runners has a
performance bottleneck - `/nix/store` hydration. Caches are monolithic archives
that must be *sequentially* transferred, written to disk, then extracted.
Network and disk I/O are heavy, CPU is pegged. For a typical 1.5G cache (6G
uncompressed) on a standard runner this means *minimum* 60s before useful work
can begin. The full cache must be transferred on every job, post-job the store
must be re-archived and uploaded. Caches lack granularity and scale poorly with
input graph size.

This is extremely wasteful in terms of both compute/energy and engineer flow.

~~This is the unavoidable tax on purity.~~

This *was* the unavoidable tax on purity.

Nix seed provides seed OCI images with Nix and the project dependencies baked
in. OCI layers are content-addressed, so naturally support re-use and extreme
cacheability, and are pulled and mounted *in parallel*, without full extraction.

Performance characteristics:

- **CI runner (VM) provisioning:** ~5s (fixed provider cost)
- **Layer pull + mount:** \<5s (with runner-local registry, e.g. GHCR)
- **Source fetch:** unchanged
- **Build execution:** unchanged

Replacing `actions/cache` with OCI layers makes build artifacts explicit. Once
artifact identity became first-class, release could no longer be treated as a
procedural step. Release is authority. Nix seed provides trust postures that
make that authority explicit.

> Supply chain, secured: **$$$**.
>
> Dependencies realised, once: **$$$**.
>
> Flow state, uninterrupted: **Priceless**.

## Trust

Nix Seed provides three trust postures: Innocent, Credulous, and Zero.

The default posture is Innocent.

### Trust Posture: Innocent

> **“IDGAF about trust. Gimme Perf!”**
>
> 99.999% of engineers polled

Innocent posture performs builds on a single CI provider.

- Guarantee: None.
- Attack Surface: CI provider, Nix binary cache infrastructure.
- Resiliency: Bounded by CI provider.
- Cost: Provider-bound.

### Quorum-Based

Quorum-based postures require an N-of-M quorum of builders operating in
independent failure domains (organisational, jurisdictional, and
infrastructural) to attest bitwise-identical output. Forgery effort compounds
with quorum size.

Guarantee: No single builder can forge a release.

Recommended quorum: **3 builders** with a **2-of-3** quorum.

- Tolerates single builder outage without blocking promotion.
- Prevents a single compromised builder from forging a release.
- Trade-off: if an attacker can disable one builder, only two compromises are
  required.

Increasing quorum from 2-of-3 to 3-of-4 raises required compromises from 2 to 3
— a 50% increase in attack effort.

Integrity scales with the quorum threshold (k), not the total number of builders
(n). Adding builders without raising quorum improves availability, not security.

#### Trust Posture: Credulous

> **“Trust, but verify.”**
>
> — Ronald Reagan (from Russian proverb), 1987

> **“I Want To Believe.”**
>
> — Fox Mulder, *The X-Files*, 1993

Credulous posture anchors trust on the Rekor public-good instance. Promotion is
performed by a Release Node after quorum verification.

- Attack Surface: Builder set, OIDC trust roots, Release Node, Rekor, Nix binary
  cache infrastructure.
- Resiliency: Provider-bound. Rekor public-good has a 99.5% SLO (not SLA);
  downtime blocks block build and verify.
- Cost: Provider-bound. Rekor public-good is free.

Builders run witness/gossip checks against Rekor both as part of build and on a
schedule; mismatches indicate split-view/equivocation. A self-hosted
witness/gossip check is recommended.

> [!WARNING]
>
> Credulous posture does not mitigate compromise of Nix binary cache
> infrastructure; if all builders consume the same poisoned cache, malicious
> output will satisfy quorum.

#### Trust Posture: Zero

> **“Ambition must be made to counteract ambition.”**
>
> — James Madison, *Federalist No. 51*, 1788

> **“Everyone has a plan until they get punched in the mouth.”**
>
> — Mike Tyson, 2002

Zero assumes that any actor may be compromised or coerced.

Binary caches are not trusted; builders must perform full-source bootstrap.

Promotion occurs mechanically upon quorum verification.

No Release Node exists; enforcement is contract-based.

Ethereum anchors trust and enforces quorum rules; build integrity remains
defined by builder consensus.

Contracts are upgradeable under multi-signature, time-delayed governance.

Governance cannot alter finalised releases, but can modify future validation
rules.

Structure constrains power. Verification replaces trust.

- Attack Surface: Governance keys, misconfiguration, [hardware
  interdiction](./DESIGN.md#hardware-interdiction).
- Resiliency: High.

##### Cost

Full-source bootstrap (genesis build) is expensive. Wire Jansen's [full-source
bootstrap thesis](https://nzbr.github.io/nixos-full-source-bootstrap/thesis.pdf)
reports ~17h30m on 12 logical cores / 16 GiB RAM - ~200 CPU-hours.

Cost scales with:

- Builders
- Systems
- Toolchain churn. A [script](./scripts/toolchain_churn.py) is provided to
  estimate cadence from toolchain-critical path changes (events/week
  and median days-between-events)

Order-of-magnitude example (3 builders × 4 systems): ~2400 CPU-hours per full
bootstrap event ≈ $100–$200 at typical rates ($0.04–$0.08 per vCPU-hour).

Contract enforcement cost ≈ Ξ0.001–Ξ0.003 (~$3–$9 @ Ξ1=$3k)

## Documentation

- [Overview](./OVERVIEW.md) Problems and solutions, plain-English.
- [Design](./DESIGN.md) Full design spec, unavoidably-technical.

## Quickstart / Evaluation

Add `nix-seed` to your `flake.nix` and expose `seed` in `packages`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-seed = {
      url = "github:0compute/nix-seed/v1";
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
          # placeholder: replace
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

> [!NOTE]
>
> The examples below are GitHub-specific. The approach applies to any CI.
>
> Seed and project builds require `id-token: write` permission.
>
> If outputs include an OCI image, like seed build, the `packages: write`
> permission is required.

> [!WARNING]
>
> Untrusted pull requests that modify `flake.lock` **MUST NOT** trigger seed or
> project builds.

### .github/workflows/seed.yaml

```yaml
name: seed

on:
  push:
    branches:
      - master
    paths:
      - flake.lock
  workflow_dispatch:
jobs:
  seed:
    permissions:
      contents: read
      id-token: write
      packages: write
    strategy:
      matrix:
        os:
          - macos-15
          - macos-15-intel
          - ubuntu-22.04
          - ubuntu-22.04-arm
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v6
      - uses: 0compute/nix-seed/seed@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### .github/workflows/build.yaml

```yaml
on:
  push:
    branches:
      - master
    paths-ignore:
      - flake.lock
  workflow_run:
    workflows:
      - seed
    types:
      - completed
jobs:
  build:
    if: ${{
      github.event_name == 'push' ||
      github.event.workflow_run.conclusion == 'success'
    }}
    permissions:
      contents: read
      id-token: write
    strategy:
      matrix:
        os:
          - macos-15
          - macos-15-intel
          - ubuntu-22.04
          - ubuntu-22.04-arm
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v6
      - uses: 0compute/nix-seed@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          cachix_cache: <name>
          cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

## Production Configuration

> [!WARNING]
>
> The [Design](./DESIGN.md) document contains critical security information.
>
> Read it. Twice. Or, get pwned.

Update `seedCfg` to use a quorum-based posture and define builders:

```nix
seedCfg = {
  trust = "credulous";
  builders = {
    github.master = true;
    gitlab = {};
    scaleway = {};
  };
  quorum = 2;
};
```

Builder independence requirements are detailed in
[Threat Actors](./DESIGN.md#threat-actors).

### Builder Repository Sync

`nix-seed` includes a helper to initialise and configure builder repositories to
mirror the source repository.

Provider credentials must be present in the environment.

```sh
nix run github:0compute/nix-seed/v1#sync
```
