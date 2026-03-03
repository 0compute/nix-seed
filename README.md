
# Nix Seed

Nix on ephemeral CI.

Source-only change: **build setup <10s**.

Dependencies via OCI layers.

Explicit, configurable trust anchors.

> Supply chain, secured: **$$$**.  
>
> Dependencies realised, once: **$$$**.  
>
> Flow state, uninterrupted: **Priceless**.

Docs → [Design](./DESIGN.md) / [Threat Actors](./THREAT-ACTORS.md) / [Plain-English Overview](./PLAIN-ENGLISH.md)

## OCI Layers vs `actions/cache`

`actions/cache` operates by:

1. Downloading a monolithic archive.
2. Writing it to disk.
3. Extracting it sequentially.
4. Re-archiving and uploading post-job.

This results in:

- High network and disk I/O
- Serialisation bottlenecks
- Full dataset copy on every job
- Poor scaling with cache size

OCI layers:

- Layer pulls are parallelised
- Deduplication is automatic
- Filesystems mount layered content without full extraction
- Only changed layers are transferred

Observed characteristics:

- **VM provisioning:** ~5s (fixed provider cost)
- **Layer pull + mount:** <5s (with runner-local registry, e.g. GHCR)
- **Source fetch:** unchanged
- **Build execution:** unchanged

## Trust

Nix Seed began as a performance optimisation. Replacing `actions/cache` with OCI
layers made build artifacts explicit. Once artifact identity became first-class,
release could no longer be treated as a procedural step. Release is authority.
The trust postures below make that authority explicit.

Nix Seed provides four trust postures. Choose one.

### Trust Posture: Innocent

> **“IDGAF about trust. Gimme the Fast!”**  
>
> — Every engineer ever born of woman

Innocent performs builds on a single CI runner.

- Guarantee: None.
- Attack Surface: CI provider, Nix binary cache infrastructure.
- Resiliency: Bounded by CI provider.
- Cost: Provider-bound.

### Aware

#### Quorum

Quorum semantics apply to Transparent and Zero:

- Quorum is a defined N-of-M threshold.
- Builders must operate in independent failure domains (organisational,
  jurisdictional, infrastructural).
- Builders must attest bitwise-identical output.

- Guarantee: No single builder can forge a release; compromise requires quorum
  capture.
- Attack Surface: Builder set, OIDC trust roots.
- Resiliency: Requires coordinated compromise across independent domains.

##### Recommended Quorum

Default recommendation: **3 builders** with a **2-of-3** quorum.

- Tolerates one builder outage without blocking promotion.
- Prevents a single compromised builder from forging a release.
- Trade-off: if an attacker can disable one builder, only two compromises are
  then required.

Increasing quorum from 2-of-3 to 3-of-4 raises required compromises from 2 to 3
— roughly a 50% increase in attack effort.

Integrity scales with the quorum threshold (k), not the total number of builders
(n). Adding builders without raising quorum improves availability, not security.

#### Transparent

Transparent retains conventional CI promotion and binary cache consumption.
Promotion is performed by a Release Node after quorum verification. Transparency
is anchored on the public-good Rekor instance.

- Attack Surface: Release Node, public-good Rekor, Nix binary cache
  infrastructure.
- Resiliency: public-good Rekor has a 99.5% SLO (not an SLA); downtime blocks
  block build and verify.

Builder quorum does not mitigate compromise of shared Nix binary cache
infrastructure; if all builders consume a poisoned cache, identical malicious
output can still satisfy quorum.

##### Trust Posture: Credulous

> **“I Want To Believe.”**  
>
> — Fox Mulder, *The X-Files*, 1993

Uses a single public-good transparency log.

- Resiliency: Provider-bound.
- Cost: Provider-bound.

##### Trust Posture: Suspicious

> **“Trust, but verify.”**  
>
> — Ronald Reagan, 1987

Extends transparency to a K-of-L log quorum.

- Resiliency: Tolerates single-log failure or capture.
- Cost: Moderate operational overhead.

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

Ethereum enforces quorum rules and anchors release validity; build integrity
remains defined by builder consensus.

Contracts are upgradeable under multi-signature, time-delayed governance.  
Governance cannot alter finalised releases, but can modify future validation
rules.

Forgery effort compounds with each independent failure domain.

Structure constrains power. Verification replaces trust.

##### Cost

Full-source bootstrap (“genesis build”) is expensive.  The [NixOS full-source
bootstrap thesis](https://nzbr.github.io/nixos-full-source-bootstrap/thesis.pdf)
reports ~17–18 hours on 12 logical cores / 16 GiB RAM — roughly **~200
vCPU-hours per system per builder**.

Total cost scales with:

- **Builders (M)**
- **Systems (S)**
- **Bootstrap cadence**

Order-of-magnitude example (3 builders × 4 systems):

- ~2,400 vCPU-hours per full bootstrap event
- ≈ $100–$200 compute cost at typical cloud rates ($0.04–$0.08 per vCPU-hour)
- Contract enforcement cost ≈ Ξ0.001–Ξ0.003 (~$3–$9 @ Ξ1=$3k)

Zero is materially more expensive than Transparent. The guarantee reflects that.

## Quickstart / Evaluation

> [!WARNING]
>
> Trust Posture: Innocent is **not recommended for production**.

Add `nix-seed` to your `flake.nix` and expose `seed` and `seedCfg`:

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
          default = pkgs.hello;

          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };
        }
      );

    seedCfg.trust = "innocent";
  };
}
```

> [!NOTE]
>
> The examples below are GitHub-specific. The approach applies to any CI.

> [!WARNING]
>
> Seed and project builds require `id-token: write` permission.
>
> If outputs include an OCI image, `packages: write` is also required.
>
> Untrusted pull requests that modify `flake.lock` **must not** trigger
> seed or project builds.

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
  trust = "credulous";  # or "suspicious"

  builders = {
    github.master = true;
    gitlab = {};
    scaleway = {};
  };

  quorum = 2;
};
```

Builder independence requirements are detailed in
[Threat Actors](./THREAT-ACTORS.md).

### Builder Repository Sync

`nix-seed` includes a helper to initialise and configure builder repositories
to mirror the source repository.

Provider credentials must be present in the environment.

```sh
nix run github:0compute/nix-seed/v1#sync
```
