# Nix Seed

Nix on ephemeral CI: happy-path (app src change only) **build starts in seconds**.

Dependency closure ships as content-addressed OCI layers; signed provenance
and SBOM included.

> Dependencies realized, once: $$$.
>
> Flow state, uninterrupted: $$$.
>
> A build guaranteed by Hard Math: Priceless.

Full breakdown and threat model: [Design](./DESIGN.md).

Lost in the jargon? Got you: [Plain English](./PLAIN-ENGLISH.md).

<!--
AGENT: glossary should become a soft into for non-technical readers. Many of the
defined terms should be replaced in this doc and DESIGN.md with the link to
further info
-->

## Trust

> Just because you're paranoid doesn't mean they aren't after you.
>
> - Anonymous, c. 1967

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
> - Fox Mulder, The X-Files

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

> Security Doctrine: Trust No Fucker.

[Zero](./DESIGN.md#zero) anchors trust on an Ethereum L2 smart contract with an
N-of-M independent builder quorum.

- Guarantee: Hard Math. No builder, organisation, or jurisdiction can forge a
  release. Source:
  - **Full-Source Bootstrap**
  - **Immutable Ledger**
  - **No Central Actor**
  - **Contract-Enforced Builder Independence**
- Attack Surface: Misconfiguration, governance keys, [hardware
  interdiction](./DESIGN.md#hardware-interdiction).
- Resiliency: High.
- Cost (assuming 3 builders across 4 systems): 0.001 to 0.003 ETH ($3 to $9 at
  ETH = $3,000).

> [!NOTE]
>
> Zero is not yet implemented.
>
> Funding applications pending: NLnet, Sovereign Tech Fund.

## Quickstart/Evaluation

> [!WARNING]
>
> Do not use [Innocent](#trust-level-innocent) in production. Minimum:
> [Credulous](#trust-level-credulous).

Add `nix-seed` to your flake and expose `seed` and `seedCfg`:

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
          # seed is passed flake self, realizes inputs of all flake outputs
          seed = inputs.nix-seed.lib.mkSeed {
            inherit pkgs;
            inherit (inputs) self;
          };
        }
      );
    seedCfg.trust = "naive";
  };
}
```

> [!NOTE]
>
> This is GitHub-specific. The approach applies to any CI.

> [!WARNING]
>
> Seed and project builds require `id-token: write` permission. Seed build, and
> project build if outputs include a container image, require `packages:
> write`.
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
      # extend if additional dependency sources exist (e.g. pyproject.toml);
      # build workflow paths-ignore MUST match
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
      - uses: 0compute/nix-seed@v1/seed
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

Update `seedCfg`: set `trust` to `credulous` and define `builders` and
`quorum`. See [Threat Actors](./DESIGN.md#threat-actors) for guidance on
builder independence.

> [!NOTE]
>
> This is the only option until [Trust Level: Zero](#trust-level-zero) is
> implemented. Refer to [Trust Level: Credulous](#trust-level-credulous) for
> guarantee and attack surface detail.

```nix
# in flake outputs
seedCfg = {
  trust = "credulous";
  builders = {
    aws = { };
    gcp = { };
    github.master = true;
    gitlab = { };
    scaleway = { };
  };
  # allow 1-of-5 builders to be down
  quorum = 4;
};
```

`nix-seed` includes a sync helper that creates and configures builder repos to
mirror the source repository. Provider credential tokens must be set in the environment.

```sh
nix run github:0compute/nix-seed/v1#sync
```
