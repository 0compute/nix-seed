
# Nix Seed

Nix on ephemeral CI.

Source-only change: **build setup <10s**.

Dependencies via OCI layers.

Explicit, configurable trust anchors.

> Supply chain, secured: **$$$**.  
> Dependencies realised, once: **$$$**.  
> Flow state, uninterrupted: **Priceless**.

Docs → [Design](./DESIGN.md) / [Threat Actors](./THREAT-ACTORS.md) / [Plain-English Overview](./PLAIN-ENGLISH.md)

---

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

---

Nix Seed began as a performance optimisation. Replacing `actions/cache` with OCI
layers made build artifacts explicit. Once artifact identity became first-class,
release could no longer be treated as a procedural step. Release is authority.
The trust postures below make that authority explicit.

---

## Trust

Nix Seed provides trust postures. Choose one.

---

### Trust Posture: Innocent

> **“IDGAF about trust. Gimme the Fast!”**  
> — Every engineer ever born of woman

Innocent performs builds on a single CI runner.

- Guarantee: None.
- Attack Surface: CI provider, Nix binary cache infrastructure.
- Resiliency: Bounded by CI provider.
- Cost: Provider-bound.

---

## Aware

### Quorum

Quorum semantics apply to Transparent and Zero:

- Quorum is a defined N-of-M threshold.
- Builders must operate in independent failure domains (organisational, jurisdictional, infrastructural).
- Builders must attest bitwise-identical output.

- Guarantee: No single builder can forge a release; compromise requires quorum capture.
- Attack Surface: Builder set, OIDC trust roots.
- Resiliency: Requires coordinated compromise across independent domains.

#### Recommended quorum

Default recommendation: **3 builders** with a **2-of-3** quorum.

- Tolerates one builder outage without blocking promotion.
- Prevents a single compromised builder from forging a release.
- Trade-off: if an attacker can disable one builder, only two compromises are then required.

Increasing quorum from 2-of-3 to 3-of-4 raises required compromises from 2 to 3 — roughly a 50% increase in attack effort.

Integrity scales with the quorum threshold (k), not the total number of builders (n). Adding builders without raising quorum improves availability, not security.

---

### Transparent

Transparent retains conventional CI promotion and binary cache consumption.
Promotion is performed by a Release Node after quorum verification.
Transparency is anchored on the public-good Rekor instance.

- Attack Surface: Release Node, public-good Rekor, Nix binary cache infrastructure.

Builder quorum does not mitigate compromise of shared Nix binary cache infrastructure; if all builders consume a poisoned cache, identical malicious output can still satisfy quorum.

#### Trust Posture: Credulous

> **“I Want To Believe.”**  
> — Fox Mulder, *The X-Files*, 1993

Uses a single public-good transparency log.

- Resiliency: Provider-bound.
- Cost: Provider-bound.

#### Trust Posture: Suspicious

> **“Trust, but verify.”**  
> — Ronald Reagan, 1987

Extends transparency to a K-of-L log quorum.

- Resiliency: Tolerates single-log failure or capture.
- Cost: Moderate operational overhead.

---

### Trust Posture: Zero

> **“Ambition must be made to counteract ambition.”**  
> — James Madison, *Federalist No. 51*, 1788  
>
> **“Everyone has a plan until they get punched in the mouth.”**  
> — Mike Tyson, 2002

Zero assumes that any actor may be compromised or coerced.

Binary caches are not trusted; builders must perform full-source bootstrap.

Promotion occurs mechanically upon quorum verification.  
No Release Node exists; enforcement is contract-based.

Ethereum enforces quorum rules and anchors release validity; build integrity
remains defined by builder consensus.

Contracts are upgradeable under multi-signature, time-delayed governance.  
Governance cannot alter finalised releases, but can modify future validation rules.

Forgery effort compounds with each independent failure domain.

Structure constrains power. Verification replaces trust.

---

## Quickstart

Add `nix-seed` to your `flake.nix`:

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
        let pkgs = inputs.nixpkgs.legacyPackages.${system};
        in {
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

---

## GitHub Workflows (Example)

### .github/workflows/seed.yaml

```yaml
name: seed
on:
  push:
    branches: [ master ]
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
    branches: [ master ]
    paths-ignore:
      - flake.lock
  workflow_run:
    workflows: [ seed ]
    types: [ completed ]

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
```

---

## Production Configuration

Set trust to `credulous` or `suspicious`, define builders and quorum:

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

Refer to the Design document for detailed governance and Zero posture configuration.
