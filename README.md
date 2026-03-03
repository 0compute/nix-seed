# Nix Seed

Nix on ephemeral CI.

Source-only change: **build setup \<10s**.

Dependencies via [OCI] layers.

Explicit trust anchors.

> Supply chain, secured: **$$$**.
>
> Dependencies realized, once: **$$$**.
>
> Flow state, uninterrupted: **Priceless**.

Docs → [Design](./DESIGN.md) / [Threat Actors](./THREAT-ACTORS.md) /
[Plain-English Overview](./PLAIN-ENGLISH.md).

## OCI Layers vs `actions/cache`

`actions/cache` operates by:

1. Downloading a monolithic archive.
1. Writing it to disk.
1. Extracting it sequentially.
1. Re-archiving and uploading post-job.

This means:

- High network/disk I/O.
- Serialization bottlenecks.
- Full dataset copy on every job.
- Poor scaling with cache size.

OCI layers are content-addressed:

- Layer pulls are parallelized.
- Deduplication is automatic.
- Filesystems mount layered content without full extraction.
- Only changed layers are transferred.

Observed characteristics:

- **VM provisioning:** ~5s (fixed provider cost)
- **Layer pull + mount:** \<5s (with runner-local registry i.e. GHCR)
- **Source fetch:** unchanged
- **Build execution:** unchanged

## Trust

> **“Just because you're paranoid doesn't mean they aren't after you.”**
>
> - Anonymous, c. 1967

Nix Seed provides three trust modes. Choose one.

### Trust Level: Innocent

> **“IDGAF about trust. Gimme the Fast!”**
>
> - Every Engineer Every Born of Woman

[Innocent](./DESIGN.md#innocent) anchors trust on the Rekor public-good instance
with a single builder.

- Guarantee: None.
- Attack Surface: Builder, Rekor, and Nix cache infra - all central actors, all
  [.gov](./DESIGN.md#usa)-capturable.
- Resiliency: Rekor has no SLA; downtime blocks build and verify.
- Cost: Free.

### Trust Level: Credulous

> **“I Want To Believe.”**
>
> - Fox Mulder, The X-Files, 1993

[Credulous](./DESIGN.md#credulous) anchors trust on the Rekor public-good
instance with an N-of-M independent builder quorum.

When the configured builder quorum is reached, the Master Builder creates a
signed git tag (format configurable) on the source commit.

- Guarantee: No builder, organisation, or jurisdiction, **except
  [.gov](./THREAT-ACTORS.md#usa) or a compromised Master Builder**, can forge a
  release.
- Attack Surface: As for [Innocent](#trust-level-innocent). The Master Builder,
  as a central actor, is a juicy target.
- Resiliency: As for [Innocent](#trust-level-innocent).
- Cost: Free.

## Trust Level: Zero

> **“Ambition must be made to counteract ambition.”**
>
> — James Madison, *Federalist No. 51*, 1788

> **“Everyone has a plan until they get punched in the mouth.”**
>
> — Mike Tyson

[Zero](./DESIGN.md#zero) assumes that any actor may be compromised or coerced.

Validity is defined by quorum, not by authority.

Identical output must be attested across independent failure domains.

Forgery effort compounds with each additional independent failure domain.

Promotion occurs mechanically upon quorum verification.

Structure constrains power. Verification replaces trust.

- Guarantee: Hard Math. Trust is anchored on an Ethereum L2 smart contract with
  an N-of-M independent builder quorum. Backing:
  - **Full-source bootstrap**
  - **Immutable ledger**
  - **Contract-enforced builder independence**
  - **No central actor**
- Attack Surface: Governance keys, misconfiguration, [hardware
  interdiction](./DESIGN.md#hardware-interdiction).
- Resiliency: High.
- Cost (3 builders, 4 systems): Ξ0.001–Ξ0.003 (~$3–$9 @ Ξ1=$3k).

> [!WARNING]
>
> Full-source bootstrap "Genesis Build" is expensive. The [NixOS Full-Source
> Bootstrap
> thesis](https://nzbr.github.io/nixos-full-source-bootstrap/thesis.pdf) reports
> ~17h30m on 12 logical cores / 16 GiB RAM,
> a baseline of ~200 vCPU-hours per genesis run. Estimate
> order-of-magnitude only; cost scales with builders x systems (M x S) for each
> full bootstrap event.
>
> For rough cadence planning, run
> [`scripts/toolchain_churn.py`](./scripts/toolchain_churn.py) against a local
> nixpkgs clone to count toolchain-critical churn (events/week and median days
> between events).

## Quickstart/Evaluation

> [!WARNING]
>
> [Innocent](#trust-level-innocent) is NOT recommended for production.

Add `nix-seed` to your `flake.nix` then expose `seed` and `seedCfg`:

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
    seedCfg.trust = "innocent";
  };
}
```

> [!NOTE]
>
> The below is GitHub-specific. The approach applies to any CI.

> [!WARNING]
>
> Seed and project builds require `id-token: write` permission. Seed build, and
> project build, if outputs include an OCI image, requires
> `packages: write`.
>
> Untrusted pull requests with changes to `flake.lock` **MUST NOT** trigger
> build of seed or project.

<!--
TODO: Project is capable of generating these workflows. Do that instead and
explain that this is a "rendered" example.
-->

### .github/workflows/seed.yaml

```yaml
name: seed
on:
  push:
    branches:
      - master
    paths:
      # extend with additional sources of dependency truth (e.g. Cargo.lock,
      # poetry.lock, package-lock.json, go.sum)
      # WARNING: build workflow `paths-ignore` MUST match
      - flake.lock
  # permit manual start
  workflow_dispatch:
jobs:
  seed:
    permissions:
      # allow checkout and other read-only ops; this is the default, but
      # specifying a permissions block drops the default to `none`
      contents: read
      id-token: write
      packages: write
    strategy:
      matrix:
        # MUST match os list in `build` workflow.
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
          # optional; recommended
          cachix_cache: <name>
          cachix_auth_token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

## Production Configuration

> [!WARNING]
>
> The [design doc](./DESIGN.md) details critical security information.
>
> Read it. Twice. Or, get pwned.

> [!NOTE]
>
> This is the only option until [Zero](#trust-level-zero) is implemented. Refer
> to [Credulous](#trust-level-credulous) for guarantee and attack surface
> detail.

Update `seedCfg` setting `trust = "credulous"`, then define `builders` and
`quorum`.

See [Threat Actor Mitigations](./THREAT-ACTORS.md#mitigations) for
builder-independence guidance.

```nix
# in flake outputs
seedCfg = {
  trust = "credulous";
  builders = {
    github.master = true;
    gitlab = { };
    scaleway = { };
  };
  # 1 builder down does not block quorum
  quorum = 2;
};
```

`nix-seed` includes a sync helper that creates and configures builder repos to
mirror the source repository. Provider credential tokens must be set in the
environment.

```sh
nix run github:0compute/nix-seed/v1#sync
```

______________________________________________________________________

[oci]: https://opencontainers.org/
