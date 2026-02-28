# Nix Seed: Design

The design goal is time-to-build (setup phase) performance.

Content-addressing, reproducibility, and the auditable bootstrap chain are
properties of `nixpkgs` and `nix2container` — not added by this system. The
trust model is a free consequence of the performance model.

## Architecture

The release pointer is the image digest,
`ghcr.io/org/repo.seed@sha256:<digest>`, or digest of other build result NAR.
Registry tags and metadata are non-authoritative.

Layering is delegated to `nix2container`. Execution is handled by external
workflow scripts.

### Performance

- Closure realization is replaced by pulling and mounting an OCI filesystem
  image.
- Setup cost scales with dependency change since the last seed.
- Source fetch (shallow clone size) is unchanged.
- Build execution time is unchanged.

#### Constraints

- Requires an OCI registry. A CI provider with a co-located registry is
  preferred for performance, but not required.
- Darwin builds must be run on macOS builders if they need Apple SDKs. A runner
  with a differing SDK version produces a differing NAR hash and fails
  deterministically.

#### Instrumentation

Jobs are instrumented with OpenTelemetry spans for:

- seed pull
- mount ready
- build start
- seed build (when a new seed is required before the app build)
- digest verification

Primary metric: time-to-ready (setup only).

#### Comparisons

This project can generate CI workflows that compare setup-time overhead against
cache-based approaches (e.g. public binary cache, cache actions).

These workflows are not required for correctness and are intended for
benchmarking / demonstration.

The benchmark command is:

- `nix develop -c true`

### Seed Construction

1. A seed build evaluates a Nix-built project.
1. `nix2container` produces an OCI image of the dependency closure whose layers
   correspond to store paths. The image digest is available from nix2container
   metadata before push.
1. The image is pushed to an OCI registry.
1. The registry-reported digest is verified against the nix2container-computed
   digest. Mismatch aborts.

`nix2container` is a pinned flake input; its version and hash are verified by
the Nix build system under the same supply chain trust model as all other
dependencies.

### Trust

#### Bootstrap Chain

> The source was clean, the build hermetic, but the compiler was pwned.

[Trusting trust](https://dl.acm.org/doi/10.1145/358198.358210) has no software
fix — the compiler chain must terminate at a ground truth small enough for a
human to audit.

Nixpkgs realizes this by building every compiler, linker, and library from
source, terminating at a minimal binary seed.

**Stage0.** The initial binary is
[stage0-posix](https://github.com/oriansj/stage0-posix): a self-hosting
assembler whose bootstrap binary is a few hundred bytes of hex-encoded machine
instructions. There is no opaque compiler binary to trust.

From stage0, the chain builds through
[GNU Mes](https://www.gnu.org/software/mes/) — a minimal C compiler and Scheme
interpreter bootstrapped entirely from the assembler — then through tcc and gcc,
arriving at the full toolchain. The upper layers are handled by
[live-bootstrap](https://github.com/fosslinux/live-bootstrap). The entire chain
is coordinated with [bootstrappable.org](https://bootstrappable.org/).
The nixpkgs implementation lives in
[`pkgs/stdenv`](https://github.com/NixOS/nixpkgs/tree/master/pkgs/stdenv).

**The cost is already paid.** The full source bootstrap exists in the nixpkgs
dependency graph regardless of this project. Seed images cache its output: the
first build after a seed update pays the full bootstrap cost once; subsequent CI
jobs pull prebuilt layers. Trustworthiness is not added overhead — it is a
property of the build graph that seed images happen to preserve.

Consumers who want independent verification can rebuild from the stage0 binary,
reproduce the full closure, and check the digest against the anchored value. The
content-addressed layers provide a direct correspondence between what is pulled
and what was built.

#### Quorum

> [!WARNING]
>
> Reproducible builds are a hard prerequisite. Without reproducibility,
> diverging digests are indistinguishable from a subverted build — the system
> cannot determine which builder is correct and quorum fails permanently.
>
> Verify with `nix build --check`. See
> [reproducible-builds.org](https://reproducible-builds.org/).

Releases may require N-of-M builder agreement on the image digest.

Quorum is only meaningful if builders span independent failure domains:
organization, jurisdiction, infrastructure, and identity issuer.

**Signing identity independence** requires that no single operator controls the
signing identities of multiple quorum builders. In standard mode, identity is
established via OIDC issuer: GitHub Actions
(`token.actions.githubusercontent.com`) and Azure Pipelines
(`vstoken.dev.azure.com`) share a Microsoft-controlled issuer and do not satisfy
identity independence when combined. In L2-anchored mode, identity is
established by registered contract key; OIDC issuer is not a factor.

**Choosing N:** each of the N required builders should have a distinct
`corporateParent`, `jurisdiction`, and signing identity. N ≥ 3 is a practical
minimum; below that a single adversary controlling two independent entities can
forge a majority. Unanimous (M-of-M) is the strongest guarantee. See
[`modules/seedcfg.nix`](modules/seedcfg.nix) and
[`modules/builders.nix`](modules/builders.nix) for the builder registry schema.

**Timing:** in standard mode with N-of-M and a deadline, a party controlling M-N
builders can delay attestation to ensure the deciding N-th vote comes from a
builder of their choice. L2-anchored mode eliminates this: attestations
accumulate indefinitely and quorum is declared when the threshold is met, not
when a timer expires.

If builders disagree on the digest, release fails.

#### Standard Mode

> [!WARNING]
>
> **Not for production.** Standard mode depends on Rekor[^rekor]
> availability and external OIDC[^oidc] trust roots. Use
> [L2-anchored mode](#l2-anchored) for production releases.

Each project maintains a `.seed.lock` containing a digest per target system:

```json
{
  "aarch64-darwin": "sha256:...",
  "aarch64-linux": "sha256:...",
  "x86_64-darwin": "sha256:...",
  "x86_64-linux": "sha256:..."
}
```

If no digest exists for a system, the seed is built, locked, and the normal
build proceeds.

After each build, an in-toto statement is generated describing inputs and build
metadata, signed via OIDC[^oidc]/KMS[^kms] using cosign[^cosign],
logged to Rekor[^rekor], and attached to the image as an OCI artifact. No
mutable registry state is trusted.

At minimum, the statement must bind:

- source repository URI
- source commit digest
- flake.lock content hash
- target `system`
- output image digest
- builder identity and issuer
- build timestamp and workflow run ID

**Consumption:**

1. Read seed digest for the current system from `.seed.lock`.
1. Verify: attestation signature is valid; Rekor log inclusion is valid;
   statement contents match expected inputs.
1. Execute build steps in seed container by digest.

> [!WARNING]
>
> Rekor has no enterprise SLA. If Rekor is unavailable, quorum cannot be
> reached and builds fail. For production use, use
> [L2-anchored mode](#l2-anchored).

#### L2-Anchored

> [!WARNING]
>
> **No substituters.** Each builder must build its closure locally from source
> with binary caches disabled. Build independence is the source of quorum's
> security guarantee: N builders on N independent stacks must all produce the
> same digest. If builders substitute from a shared cache, the cache operator —
> not N independent builds — is what produced the attested digest. The
> independence constraints the contract verifies (`corporateParent`,
> `jurisdiction`, infrastructure) are vacuous if all builders are serving the
> same pre-built narinfo.

> [!NOTE]
>
> The L2 contract maintains a builder revocation list. If a builder is
> retroactively found compromised, its identity is added to the list; the
> contract excludes its attestations from quorum counting. Prior seed releases
> that relied on the revoked builder should be re-evaluated.

A *seed release* is a set of image digests, one per target system. This is
distinct from a project release (git tag); a project release may reference one
or more seed releases.

The `commit` field in `attest(commit, system, digest)` is the VCS commit object
ID (full 40-hex SHA-1 or full 64-hex SHA-256 depending on repository format)
of the source tree that was built. Builders must additionally attest the exact
`flake.lock` hash to bind dependency resolution.

Rekor[^rekor] is not used. Each builder holds a persistent signing key
registered in the contract at genesis. A build produces a single transaction:

```solidity
attest(commit, system, digest)
```

signed by the builder's registered key. The contract records
`(commit, system, digest, builder_address, block_number)` for each submission,
then:

1. Checks that N distinct registered builders have submitted the same
   `(commit, system, digest)` tuple.
1. Verifies independence constraints across the N builders (`corporateParent`,
   `jurisdiction`, infrastructure, substituters).
1. When quorum is satisfied across all target systems, publishes the digest tree
   as a single Merkle root:
   - hash function = `keccak256`
   - leaf bytes =
     `0x00 || u16be(len(system)) || utf8(system) || imageDigestBytes`
   - internal node bytes = `0x01 || leftHash || rightHash`
   - leaf order = lexical ascending by `system`
   - odd leaf handling = duplicate the final leaf at each level
   - root = Merkle root across all systems
1. The anchored root is immutable.

No deadline is required. The contract accumulates attestations indefinitely;
quorum is declared when the threshold is met. The blockchain is the transparency
log — no separate log service is required.

The master builder's role is reduced to monitoring the contract for the
published root. Master-builder trust is removed from the promotion path.

**Key management:** builder keys are persistent secrets held in CI secret
stores. Compromise triggers revocation via the contract's governance multi-sig
(see [Governance Constraints](#governance-constraints)). Keys are registered at
genesis and rotated by contract multi-sig.

**Why CI key compromise still matters:** the contract verifies that
`N` distinct registered builder keys signed the same tuple. It does not
distinguish an authorized signer from an attacker using a stolen key.
If fewer than `N` keys are compromised, quorum blocks promotion; if `N`
or more are compromised, a malicious digest can satisfy quorum until
revocation occurs.

Builders must enforce `substituters =` (empty) and `trusted-substituters =`
(empty), and include the effective `nix show-config` output in the attested
build metadata so verifiers can reject substituted builds.

The `.seed.lock` file is not used.

**Consumption:** The contract must not be empty; see [Genesis](#genesis).

1. Query the L2 contract for the current anchored Merkle root.
1. Verify inclusion proof for the current system; extract digest.
1. Execute build steps in seed container by digest.

Contract quorum verification subsumes attestation checks.

##### L2 Gas Costs

Gas[^gas] cost depends on calldata size, state writes, and current L2 fee
conditions. The ranges below are planning estimates, not guarantees.

- `attest(commit, system, digest)` submission:
  - expected gas: 120,000 to 220,000
  - expected cost: 0.00006 to 0.00022 ETH
  - expected USD (ETH = $3,000): about $0.18 to $0.66
- root publication (once quorum is met for all systems):
  - expected gas: 180,000 to 320,000
  - expected cost: 0.00009 to 0.00032 ETH
  - expected USD (ETH = $3,000): about $0.27 to $0.96

Total anchoring overhead per release is typically below 0.001 ETH
(about $3.00 at ETH = $3,000), excluding unusual fee spikes.

##### Genesis

The first seed has no prior quorum to bootstrap from. Genesis is a controlled
ceremony distinct from normal builds:

1. All configured builders (M-of-M, unanimous) build the seed independently from
   source.
1. Each builder submits a genesis attestation to the contract via their
   registered key.
1. The contract requires unanimous attestation and verifies full independence
   across all M builders before accepting the genesis root.
1. Genesis is finalized by a multi-signature transaction requiring all M builder
   keys; no single party can unilaterally declare genesis.
1. An empty contract state rejects all non-genesis builds. Genesis must be
   completed before any seed can be consumed.

Post-genesis builds use the standard N-of-M threshold. The genesis root is the
immutable trust anchor.

#### Governance Constraints

- Governance multi-sig must be independent from builder keys.
- Threshold should be at least 2-of-3 for emergency revocation/rotation.
- If a genesis key is lost before finalization, restart genesis with a new
  builder set and publish a signed incident record.
- If a builder is revoked post-genesis, re-evaluate affected releases and
  republish status.

#### Project Attack Surface

This project is intentionally low-code: it mainly defines build policy,
verification rules, and workflow wiring around existing Nix/Sigstore/container
systems. That limits direct application attack surface because there is little
custom runtime logic to exploit.

The primary risk is **misconfiguration**, not complex code execution. The
highest-impact failure modes are:

- accepting mutable references (tags) instead of digests,
- weak quorum/independence configuration,
- enabling substituters[^substituter] in L2[^l2] mode,
- trusting unsigned or under-specified attestations[^attestation],
- insecure key handling in CI.

Security work should prioritize strict defaults, immutable references,
verification-by-default, and auditable configuration over adding new
orchestration code.

## .gov Proofing

### Legal

All major public cloud providers — AWS, Azure, GCP, Cloudflare, Fastly, and
others — are incorporated and operated under US jurisdiction. They are subject
to the CLOUD Act, FISA Section 702, and National Security Letters, any of which
can compel infrastructure access or content disclosure without public notice.

*Sovereign cloud* offerings from these providers are marketed as
jurisdictionally isolated but remain US-operated entities under US law. An AWS
EU Region is still Amazon. An Azure Government cloud is still Microsoft.
Jurisdiction follows the operator, not the data center.

CI platforms headquartered in the US — GitHub, GitLab, CircleCI, Buildkite,
Harness, and others — inherit the same exposure regardless of where their
runners execute.

Meaningful legal isolation from US government coercion requires at least one
quorum builder to be:

- Self-hosted on hardware owned by a non-US legal entity.
- Operated in a jurisdiction with no mutual legal assistance treaty (MLAT) with
  the US, or with significant friction in its execution.
- Controlled by an organization not incorporated in the US.

For the CLOUD Act specifically: data held by a US-controlled provider is
reachable regardless of physical location. Region selection provides performance
and data residency properties only; it does not alter legal jurisdiction.

NSLs require no judicial approval and carry a gag order. The provider's
compliance team will not notify you. An administration that has fired inspectors
general in bulk, declared independent agencies optional, and installed loyalists
at the DOJ has the same legal access to your build infrastructure as any other.
The CLOUD Act does not have a carve-out for good behavior.

A quorum composed entirely of US-headquartered CI providers is legally a single
failure domain. Practically, meaningful quorum against nation-state adversaries
requires self-hosted runners.

### Extra-legal

Legal process is the slow path. A well-resourced signals intelligence agency has
better options.

**Passive collection:** UPSTREAM collection taps internet backbone traffic at
scale. PRISM provides access to major US tech company data. Rekor submissions,
registry pushes, OIDC token exchanges, and build metadata are all observable in
transit by a Five Eyes adversary without any legal process.

**Five Eyes:** the UKUSA agreement extends NSA collection to GCHQ (UK), CSE
(Canada), ASD (Australia), and GCSB (New Zealand). A builder in any Five Eyes
jurisdiction is not meaningfully separate from a US builder from an intelligence
perspective.

**Active network attack:** QUANTUM INSERT allows injection of malicious content
into unencrypted or MITM-able traffic. BGP hijacking has been used to redirect
traffic through collection points. DNS manipulation is within documented
capability.

**Hardware interdiction:** TAO's ANT catalog documents implants for network
equipment, hard drives, and server hardware. Supply chains routed through US
logistics are interdiction targets.

**Cryptographic risk:** NSA seeded a backdoor into Dual_EC_DRBG (NIST SP
800-90A). Any NIST-blessed primitive should be treated as potentially weakened.
P-256 (used in cosign/ECDSA) is NIST-approved. Prefer Ed25519 where the stack
permits.

**System impact:**

- **Standard mode:** Rekor submissions, OIDC token issuance, and registry
  traffic are all passively observable. The transparency log is transparent to
  the adversary by design.
- **L2-anchored mode:** contract transactions are public by design; no
  additional surveillance surface. Builder keys stored in CI secret stores on
  US-provider infrastructure are accessible via PRISM without the builder's
  knowledge.
- **Any mode:** a builder running on hardware that passed through US logistics
  may carry a firmware implant. A builder on a US cloud provider's VM is running
  on hardware the adversary may have pre-implanted.

**Mitigations:**

- Use Ed25519 over P-256 for all signing operations.
- Store genesis and builder keys in HSMs, not CI secret store environment
  variables. A hardware token that cannot exfiltrate the private key raises the
  cost of compromise significantly.
- At least one quorum builder should be on non-Five-Eyes hardware with a
  documented, audited supply chain.
- The L2-anchored contract design already provides the strongest available
  mitigation: N independent signers on N independent hardware stacks must all be
  compromised simultaneously. Cost scales with N.

No software-only solution running on commodity cloud hardware in an automated CI
environment is proof against a well-resourced signals intelligence agency with
hardware access. The goal is not to be NSA-proof — that requires air-gapped
hardware signing ceremonies outside the scope of CI. The goal is to make passive
supply-chain compromise of a *release* require active, targeted, multi-system
attack that is detectable, attributable, and expensive.

______________________________________________________________________

## Other Threat Actors

| Actor | Org | Capability | Mode at risk |
| --- | --- | --- | --- |
| China | MSS / PLA Unit 61398 | Supply chain, HUMINT | Standard, L2 |
| Russia | GRU / SVR / FSB | Build pipeline | Standard |
| North Korea | RGB / Lazarus Group | Credential theft | Standard, L2 |
| Iran | IRGC / APT33–APT35 | Spear phishing | Standard |
| Israel | Unit 8200 / NSO Group | Zero-day, implants | All |
| Criminal | Ransomware, insider threat | Credential theft | Standard |

### China

China's National Intelligence Law (2017)[^national-intelligence-law]
compels any Chinese entity — including Alibaba Cloud — to cooperate with
intelligence services on demand and without disclosure. A quorum that includes
Alibaba Cloud or any runner operated by a Chinese-headquartered entity is not
legally independent.

PLA Unit 61398 and MSS-linked groups (APT10, APT41) have demonstrated sustained
supply-chain targeting, including software-update hijacking and build-server
compromise. The L2-anchored design raises the cost by requiring simultaneous
compromise across N independent builder networks.

HUMINT recruitment of build-system maintainers is not addressed by any technical
control. Key ceremony discipline and HSM-resident keys limit insider blast
radius: an insider can attest a bad build, but cannot retroactively forge the
quorum.

### Russia

SUNBURST (SolarWinds)[^sunburst] is the canonical build-pipeline
attack: GRU / SVR operators
compromised the SolarWinds Orion build system and inserted a backdoor that was
signed with the legitimate code-signing key. A multi-builder quorum would not
have prevented a single-builder build compromise — but would have caught it:
independent builders would attest a *different* digest, breaking quorum and
blocking promotion.

SORM (СОРМ) requires Russian ISPs to provide FSB with real-time access to all
traffic. Runners in Russia or on Russian cloud infrastructure are subject to
passive interception regardless of TLS. Reproducible builds mean an observer who
intercepts a build gets the same artifact but cannot inject code without
breaking the digest.

### In General

The [xz-utils backdoor (2024)](https://tukaani.org/xz-backdoor/) demonstrated
that a patient attacker can socially engineer maintainer trust over years.

Controls:

- **Quorum over commits**: if any one builder's reproducible build diverges, the
  build fails.
- **CI secret store credential theft** (session tokens, registry push
  credentials) is the most common criminal vector. HSM-resident builder keys
  defeat environment-variable exfiltration. L2 mode removes the registry push
  credential from the critical path entirely: the contract controls promotion,
  not a CI secret.
- **Ransomware** targeting CI infrastructure disables builds but cannot forge
  attestations. Redundant builders provide availability.

______________________________________________________________________

## Notes

- Seeded builds execute without network access.
- Non-redistributable dependencies are represented by NAR hash; upstream changes
  cause deterministic failure.

______________________________________________________________________

## Compliance

Upstream license terms for non-redistributable SDKs are fully respected.

______________________________________________________________________


## Footnotes

[^gas]: **Gas** — The unit used to measure computational work on
  EVM-compatible chains. Transaction fee = gas used × gas price.

[^kms]: **KMS** — Key Management Service. A managed system used to store
  cryptographic keys and perform signing operations without exposing private
  key material to build scripts.

[^anchor]: **Anchor** — Writing a release fingerprint (digest or Merkle root) to
  an immutable ledger so it cannot be silently changed later.

[^ant-catalog]: **[ANT catalog](https://en.wikipedia.org/wiki/ANT_catalog)** —
  NSA's classified menu of hardware and software implants for
  targeted surveillance, leaked by Snowden in 2013. Documents
  implants for network equipment, hard drives, and server
  firmware.

[^attestation]: **Attestation** — A signed statement describing what was built,
  from which inputs, and by which builder.

[^bootstrappable-builds]: **[bootstrappable
  builds](https://bootstrappable.org/)** — project and
  community focused on enabling software to be built
  from a minimal, auditable binary seed, eliminating
  implicit trust in compiler binaries. Coordinates the
  stage0, GNU Mes, and live-bootstrap projects.

[^builder]: **Builder** — A machine or CI runner that performs a build and
  submits evidence (attestations).

[^cloud-act]: **[CLOUD Act](https://www.justice.gov/dag/cloudact)** — Clarifying
  Lawful Overseas Use of Data Act (2018). Requires US-operated
  providers to produce data stored abroad when served with a US
  warrant, regardless of physical location.

[^cosign]: **[cosign](https://docs.sigstore.dev/cosign/overview/)** — Sigstore
  tool for signing, verifying, and storing signatures and attestations
  in OCI registries.

[^digest]: **Digest** — A content fingerprint (hash). If the content changes,
  the digest changes.

[^dual-ec-drbg]: **[Dual_EC_DRBG](https://en.wikipedia.org/wiki/Dual_EC_DRBG)**
  — Dual Elliptic Curve Deterministic Random Bit Generator. A
  NIST-standardized PRNG (SP 800-90A) subsequently confirmed to
  contain an NSA-planted backdoor.

[^ed25519]: **[Ed25519](https://ed25519.cr.yp.to/)** — Edwards-curve Digital
  Signature Algorithm over Curve25519. Not NIST-standardized;
  preferred over P-256 where the stack permits.

[^fisa-section-702]: **[FISA Section
  702](https://www.dni.gov/index.php/704-702-overview)** —
  Foreign Intelligence Surveillance Act Section 702.
  Authorizes warrantless collection of communications of
  non-US persons from US-based providers.

[^five-eyes]: **[Five Eyes](https://en.wikipedia.org/wiki/Five_Eyes)** — UKUSA
  signals intelligence alliance: United States (NSA), United Kingdom
  (GCHQ), Canada (CSE), Australia (ASD), New Zealand (GCSB).
  Intelligence collected by any member is shared across all.

[^genesis]: **Genesis** — The first trusted anchoring event in L2 mode that
  initializes contract state for future quorum-based releases.

[^gnu-mes]: **[GNU Mes](https://www.gnu.org/software/mes/)** — Minimal C
  compiler and Scheme interpreter bootstrapped from the stage0
  assembler. An intermediate stage in the nixpkgs source bootstrap
  chain between stage0-posix and gcc.

[^hsm]: **[HSM](https://en.wikipedia.org/wiki/Hardware_security_module)** —
  Hardware Security Module. Tamper-resistant hardware device for
  cryptographic key storage and operations. Private keys cannot be
  exported; signing occurs inside the device.

[^in-toto]: **[in-toto](https://in-toto.io/)** — Framework for securing software
  supply chains by defining and verifying each step in a build
  pipeline via signed link metadata.

[^l2]: **[L2](https://ethereum.org/en/layer-2/)** — Ethereum Layer 2. A network
  that records transactions and ultimately settles them to Ethereum (L1).
  In this design, it is used as an immutable public ledger for release
  anchors.

[^live-bootstrap]: **live-bootstrap**
  — Project that reproducibly builds a large set of software
  packages starting from a minimal, auditable binary seed.
  Handles the upper layers of the nixpkgs full source bootstrap
  chain above GNU Mes and tcc.
  Source: <https://github.com/fosslinux/live-bootstrap>.

[^merkle-root]: **Merkle root** — A single hash that summarizes many digests and
  allows efficient inclusion proofs for each digest.

[^mlat]: **MLAT**
  — Mutual Legal Assistance Treaty. Bilateral or multilateral agreement
  for cross-border legal cooperation, including evidence requests.
  Processing time varies from months to years.
  Source: <https://en.wikipedia.org/wiki/Mutual_legal_assistance_treaty>.

[^nar]: **NAR**
  — Nix Archive. Canonical binary serialization of a Nix store path, used
  as the input to content-addressing. The NAR hash of a path must match
  its declaration; mismatch fails the build.

[^nix2container]: **[nix2container](https://github.com/nlewo/nix2container)** —
  Tool that produces OCI images from Nix store paths, mapping
  each path to a content-addressed layer to maximize cache
  reuse.

[^nsl]: **[NSL](https://www.eff.org/issues/national-security-letters)** —
  National Security Letter. Administrative subpoena issued by the FBI
  without judicial review. Carries a statutory gag order: the recipient
  cannot disclose that the letter was received.

[^oci]: **[OCI](https://opencontainers.org/)** — Open Container Initiative.
  Industry standards for container image format, distribution, and
  runtime.

[^oidc]: **[OIDC](https://openid.net/connect/)** — OpenID Connect. Identity
  layer on OAuth 2.0. Used here for keyless signing: a CI platform issues
  a short-lived OIDC token asserting the workflow identity, which cosign
  uses as the signing credential.

[^p-256]: **P-256**
  — NIST P-256 elliptic curve (secp256r1). Used in ECDSA.
  NIST-standardized and widely deployed; treat as potentially weakened
  given the Dual_EC_DRBG precedent.

[^prism]: **[PRISM](https://en.wikipedia.org/wiki/PRISM)** — NSA program for
  collection of stored internet communications directly from major US
  tech companies under FISA Section 702 authority.

[^quantum-insert]: **[QUANTUM
  INSERT](https://en.wikipedia.org/wiki/QUANTUM_INSERT)** —
  NSA/GCHQ technique for injecting malicious content into HTTP
  streams via a man-on-the-side attack. The attacker races the
  legitimate server response with a crafted packet.

[^quorum-n-of-m]: **Quorum (N-of-M)** — Out of `M` configured builders, at least
  `N` independent builders must report the same result.

[^rekor]: **[Rekor](https://github.com/sigstore/rekor)** — Sigstore's immutable,
  append-only transparency log for software supply chain attestations.
  Entries are publicly verifiable; the log is operated by the Sigstore
  project.

[^seed]: **Seed** — A prebuilt dependency base image used to reduce CI setup
  time.

[^sigstore]: **[Sigstore](https://sigstore.dev/)** — Open-source project
  providing infrastructure for signing, transparency, and
  verification of software artifacts. Comprises cosign, Rekor, and
  Fulcio.

[^slsa]: **[SLSA](https://slsa.dev/)** — Supply-chain Levels for Software
  Artifacts. Framework defining levels of supply chain integrity
  guarantees, from basic provenance (L1) to hermetic, reproducible builds
  (L4).

[^stage0-posix]: **[stage0-posix](https://github.com/oriansj/stage0-posix)** — A
  self-hosting assembler whose initial bootstrap binary is a few
  hundred bytes of hex-encoded machine instructions — small
  enough to audit by hand. The trust anchor for the nixpkgs full
  source bootstrap chain.

[^substituter]: **Substituter** — A binary cache source that serves prebuilt
  outputs instead of building locally from source.

[^tao]: **[TAO](https://en.wikipedia.org/wiki/Tailored_Access_Operations)** —
  Tailored Access Operations. NSA division responsible for active
  exploitation of foreign targets, including hardware implants and
  network-level attacks.

[^trusting-trust]: **[trusting
  trust](https://dl.acm.org/doi/10.1145/358198.358210)** —
  Attack described by Ken Thompson (1984): a compiler can be
  modified to insert a backdoor into programs it compiles,
  including a modified copy of itself, making the backdoor
  invisible in source. Defeated by bootstrapping the compiler
  chain from a human-auditable binary seed rather than an
  opaque binary.

[^upstream]: **[UPSTREAM](https://en.wikipedia.org/wiki/UPSTREAM_collection)** —
  NSA program for bulk collection of internet traffic at the backbone
  level under FISA Section 702, operating at major fiber and
  switching infrastructure.


[^national-intelligence-law]: [National Intelligence Law
  (2017)](https://www.chinalawtranslate.com/en/national-intelligence-law/).


[^sunburst]: SUNBURST (SolarWinds) reference:
  <https://en.wikipedia.org/wiki/SolarWinds>.
