# Nix Seed

Nix on ephemeral CI: happy-path (app source change only) **build setup is
functionally instant**.

Dependencies shipped as content-addressed [OCI] layers.

Explicit trust anchors built-in.

> Supply chain, secured: $$$
>
> Dependencies realized, once: $$$.
>
> Flow state, uninterrupted: Priceless.

Details?

- [Design](./DESIGN.md).
- [Threat Actors](./THREAT-ACTORS.md).
- [Plain English](./PLAIN-ENGLISH.md) for non-technical readers.

## Performance

`actions/cache` pegs the runner by forcing it to transfer a monolithic tarball
then sequentially extract it. Post-job, the sequence must be completed in
reverse.

OCI layers stream and mount concurrently over the network.

The difference is Night and Day.

- Build setup: >60s (typical `actions/cache` fetch) to \<10s.
- Source fetch time: unchanged.
- Build execution time: unchanged.

CI provider fixed startup latency (provision and boot VM) is ~5s.

Another 5s to pull/mount the OCI layers? Highly practical with a local registry
(Hello, GHCR!).

## Trust

> Just because you're paranoid doesn't mean they aren't after you.
>
> - Anonymous, c. 1967

Nix Seed provides three trust modes. Choose one.

### Trust Level: Innocent

> IDGAF about trust. Gimme the Fast!
>
> - Every Engineer Born of Woman.

[Innocent](./DESIGN.md#innocent) anchors trust on the Rekor public-good instance
with a single builder.

- Guarantee: None.
- Attack Surface: Builder, Rekor, and Nix cache infra - all central actors, all
  [.gov](./DESIGN.md#usa)-capturable.
- Resiliency: Rekor has no SLA; downtime blocks build and verify.
- Cost: Free.

### Trust Level: Credulous

> I Want To Believe.
>
> - Fox Mulder, The X-Files, 1993

[Credulous](./DESIGN.md#credulous) anchors trust on the Rekor public-good
instance with an N-of-M independent builder quorum.

When the configured builder quorum is reached, the Master Builder creates a
signed git tag (format configurable) on the source commit.

- Guarantee: No builder, organisation, or jurisdiction, **apart from
  [.gov](./DESIGN.md#usa) or a compromised Master Builder**, can forge a
  release.
- Attack Surface: As for [Innocent](#trust-level-innocent). The Master Builder,
  as a central actor, is a juicy target.
- Resiliency: As for [Innocent](#trust-level-innocent).
- Cost: Free.

### Trust Level: Zero

> In God we trust. All others must bring data.
>
> - W. Edwards Deming, c. 1980

[Zero](./DESIGN.md#zero) anchors trust on an Ethereum L2 smart contract with an
N-of-M independent builder quorum.

- Guarantee: Hard Math. No builder, organisation, or jurisdiction can forge a
  release. Source:
  - **Full-source bootstrap**
  - **Immutable ledger**
  - **No central actor**
  - **Contract-enforced builder independence**
- Attack Surface: Misconfiguration, governance keys,
  [hardware interdiction](./DESIGN.md#hardware-interdiction).
- Resiliency: High.
- Cost (assuming 3 builders across 4 systems): Ξ0.001-Ξ0.003 ($3-$9 @ Ξ1=$3k).

> [!NOTE]
>
> Zero is not yet implemented.
>
> Funding applications pending: NLnet, Sovereign Tech Fund.

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
          # seed is passed flake self; it realizes inputs for all flake outputs
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
> project build, if outputs include a container image, requires
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
