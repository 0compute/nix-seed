# Nix Seed

Nix Seed produces OCI seed images for Nix-built projects, packaging their
dependency closure as content-addressed OCI layers to eliminate per-job
reconstruction of `/nix/store`.

## Why

In environments without a pre-populated `/nix/store`, the entire dependency
closure must be realized before a build can begin. For Nix-built projects, this
setup phase can dominate total job time.

Nix Seed removes closure realization from the critical path.

Build time does not change. Setup time does.

Source must always be fetched (typically via a shallow clone). Seeded CI does
not change that constant cost.

Traditional CI setup scales with total dependency size. Seeded CI setup scales
with dependency change since the last seed.

______________________________________________________________________

## Attestation (standard mode)

For each build result (seed image/application build/etc):

- An in-toto statement is generated describing inputs and build metadata.
- The statement is signed (via OIDC or KMS) using cosign.
- The signed statement is logged to Rekor.
- The attestation is pushed to the registry as an OCI attachment.

Consumers verify:

1. Image digest matches expected value.
1. Attestation signature is valid.
1. Rekor log inclusion is valid.
1. Statement contents match expected inputs.

No mutable registry state is trusted.

[L2-anchored mode](#l2-anchored-quorum-recommended) mode does not use Rekor or
in-toto attestations.

## Quorum (optional)

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
forge a majority. Unanimous (M-of-M) is the strongest guarantee.

**Timing:** in standard mode with N-of-M and a deadline, a party controlling M-N
builders can delay attestation to ensure the deciding N-th vote comes from a
builder of their choice. L2-anchored mode eliminates this: attestations
accumulate indefinitely and quorum is declared when the threshold is met, not
when a timer expires.

If builders disagree on the digest, release fails.

## L2-Anchored Quorum (recommended)

A *seed release* is a set of image digests, one per target system. This is
distinct from a project release (git tag); a project release may reference one
or more seed releases.

Rekor is not used. Each builder holds a persistent signing key registered in the
contract at genesis. A build produces a single transaction:

```
attest(digest, system)
```

signed by the builder's registered key. The contract records
`(digest, system, builder_address, block_number)` for each submission, then:

1. Checks that N distinct registered builders have submitted the same
   `(digest, system)` pair.
1. Verifies independence constraints across the N builders (`corporateParent`,
   `jurisdiction`, infrastructure).
1. When quorum is satisfied across all target systems, publishes the digest tree
   as a single Merkle root:
   - leaf = `system || imageDigest`
   - root = Merkle root across all systems
1. The anchored root is immutable.

No deadline is required. The contract accumulates attestations indefinitely;
quorum is declared when the threshold is met. The blockchain is the transparency
log — no separate log service is required.

The master builder's role is reduced to monitoring the contract for the
published root. Master-builder trust is removed from the promotion path.

**Key management:** builder keys are persistent secrets held in CI secret
stores. Compromise triggers revocation via the contract's governance multi-sig
(see [Constraints](#constraints)). Keys are registered at genesis and rotated by
contract multi-sig.

The `.seed.lock` file is not used in L2-anchored mode; see
[Seed Lock](#seed-lock).

Consumers verify:

1. The anchored Merkle root (on-chain).
1. Inclusion proof for their target system.
1. The image digest.

Anchoring costs less than the smallest practical denomination in most
currencies.

### Genesis

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

______________________________________________________________________

## Architecture

The release pointer is the image digest:
`ghcr.io/org/repo.seed@sha256:<digest>`. Registry tags and metadata are
non-authoritative.

Layering is delegated to `nix2container`. Execution is handled by external
workflow scripts.

### Seed Construction

1. A seed build evaluates a Nix-built project.
1. `nix2container` produces an OCI image of the dependency closure whose layers
   correspond to store paths. The image digest is available from nix2container
   metadata before push.
1. The image is pushed to an OCI registry.
1. The registry-reported digest is verified against the nix2container-computed
   digest. Mismatch aborts.

**Standard mode:** an in-toto attestation is generated, signed via OIDC/KMS,
logged to Rekor, and attached to the image as an OCI artifact.

**L2-anchored mode:** the builder submits `attest(digest, system)` to the
contract. No Rekor interaction.

### Seed Lock

In standard mode, each project maintains a `.seed.lock` containing a digest per
target system.

In L2-anchored mode the `.seed.lock` is not used. Consumers query the L2
contract directly to obtain the anchored digest and inclusion proof for their
target system. The contract is the authoritative release pointer.

Structure:

```json
{
  "aarch64-darwin": "sha256:...",
  "aarch64-linux": "sha256:...",
  "x86_64-darwin": "sha256:...",
  "x86_64-linux": "sha256:..."
}
```

If no digest exists for a system:

- the build produces a seed first,
- locks,
- then proceeds with the normal build.

### Registry

An OCI registry is required.

A CI provider with a co-located registry is preferred for performance, but not
required.

### Consumption Model

### Standard mode

1. Read seed digest for the current system from `.seed.lock`.
1. Verify: attestation signature is valid; Rekor log inclusion is valid;
   statement contents match expected inputs.
1. Execute build steps in seed container by digest.

If no lock or digest is available, a seed build runs first, then the lock is
written. For L2-anchored mode the contract must not be empty; see
[Genesis](#genesis).

### L2-anchored mode

1. Query the L2 contract for the current anchored Merkle root.
1. Verify inclusion proof for the current system; extract digest.
1. Execute build steps in seed container by digest.

Contract quorum verification subsumes attestation checks. No `.seed.lock` is
read.

### Performance Model

The system changes only the setup phase:

- Closure realization is replaced by pulling and mounting an OCI filesystem
  image.
- Setup cost scales with dependency change since the last seed.
- Source fetch (shallow clone size) is unchanged.
- Build execution time is unchanged.

Reference benchmark command:

- `nix develop -c true`

### Instrumentation

Jobs are instrumented with OpenTelemetry spans for:

- seed pull
- mount ready
- build start

<!-- AGENT: any more spans? -->

Primary metric: time-to-ready (setup only).

### Constraints

- Requires an OCI registry.
- Darwin builds must be run on macOS builders if they need Apple SDKs. A runner
  with a differing SDK version produces a differing NAR hash and fails
  deterministically.
- Standard mode requires Rekor, which has no enterprise SLA. If Rekor is
  unavailable, quorum cannot be reached and builds fail. For production use,
  consider a private Rekor instance. L2-anchored mode has no Rekor dependency.
- The L2 contract maintains a builder revocation list. If a builder is
  retroactively found compromised, its identity is added to the list; the
  contract excludes its attestations from quorum counting. Prior seed releases
  that relied on the revoked builder should be re-evaluated.

______________________________________________________________________

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

| Actor | Org | Capability | Mode at risk | | ------------------ |
--------------------------- | -------------------- | ----------------- | | China
| MSS / PLA Unit 61398 | Supply chain, HUMINT | Standard, L2 | | Russia | GRU /
SVR / FSB | Build pipeline | Standard | | North Korea | RGB / Lazarus Group |
Credential theft | Standard, L2 | | Iran | IRGC / APT33–APT35 | Spear phishing |
Standard | | Israel | Unit 8200 / NSO Group | Zero-day, implants | All | |
Criminal / non-state | Ransomware, insider threat | Credential theft | Standard
|

### China

China's
[National Intelligence Law (2017)](https://www.chinalawtranslate.com/en/national-intelligence-law/)
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

[SUNBURST (SolarWinds)](https://www.mandiant.com/resources/blog/evasive-attacker-leverages-solarwinds-supply-chain-compromises-with-sunburst-backdoor)
is the canonical build-pipeline injection attack: GRU / SVR operators
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

### Criminal / Non-State

The [xz-utils backdoor (2024)](https://tukaani.org/xz-backdoor/) demonstrated
that a patient attacker — attribution is contested; circumstantial evidence
(years of operational patience, tight OPSEC, precise target selection) points to
a state-sponsored operation — can socially engineer maintainer trust over years.
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

## Comparisons

This project can generate CI workflows that compare setup-time overhead against
cache-based approaches (e.g. public binary cache, cache actions).

These workflows are not required for correctness and are intended for
benchmarking / demonstration.

The benchmark command is:

- `nix develop -c true`

(Workflows are stubbed.)

______________________________________________________________________

## Notes

- All Nix inputs are declared and hash-pinned. Nixpkgs has full source
  bootstrap.
- `nix2container` is a pinned flake input; its version and hash are verified by
  the Nix build system under the same supply chain trust model as all other
  dependencies.
- Seeded builds execute without network access.
- Non-redistributable dependencies are represented by NAR hash; upstream changes
  cause deterministic failure.

______________________________________________________________________

## Definitions

**[ANT catalog](https://en.wikipedia.org/wiki/ANT_catalog)** — NSA's classified
menu of hardware and software implants for targeted surveillance, leaked by
Snowden in 2013. Documents implants for network equipment, hard drives, and
server firmware.

**[CLOUD Act](https://www.justice.gov/dag/cloudact)** — Clarifying Lawful
Overseas Use of Data Act (2018). Requires US-operated providers to produce data
stored abroad when served with a US warrant, regardless of physical location.

**[cosign](https://docs.sigstore.dev/cosign/overview/)** — Sigstore tool for
signing, verifying, and storing signatures and attestations in OCI registries.

**[Dual_EC_DRBG](https://en.wikipedia.org/wiki/Dual_EC_DRBG)** — Dual Elliptic
Curve Deterministic Random Bit Generator. A NIST-standardized PRNG (SP 800-90A)
subsequently confirmed to contain an NSA-planted backdoor.

**[Ed25519](https://ed25519.cr.yp.to/)** — Edwards-curve Digital Signature
Algorithm over Curve25519. Not NIST-standardized; preferred over P-256 where the
stack permits.

**[FISA Section 702](https://www.dni.gov/index.php/704-702-overview)** — Foreign
Intelligence Surveillance Act Section 702. Authorizes warrantless collection of
communications of non-US persons from US-based providers.

**[Five Eyes](https://en.wikipedia.org/wiki/Five_Eyes)** — UKUSA signals
intelligence alliance: United States (NSA), United Kingdom (GCHQ), Canada (CSE),
Australia (ASD), New Zealand (GCSB). Intelligence collected by any member is
shared across all.

**[HSM](https://en.wikipedia.org/wiki/Hardware_security_module)** — Hardware
Security Module. Tamper-resistant hardware device for cryptographic key storage
and operations. Private keys cannot be exported; signing occurs inside the
device.

**[in-toto](https://in-toto.io/)** — Framework for securing software supply
chains by defining and verifying each step in a build pipeline via signed link
metadata.

**[L2](https://ethereum.org/en/layer-2/)** — Ethereum Layer 2. A scaling network
that settles to the Ethereum base chain (L1), inheriting its security guarantees
while reducing transaction cost and latency.

**[MLAT](https://en.wikipedia.org/wiki/Mutual_legal_assistance_treaty)** —
Mutual Legal Assistance Treaty. Bilateral or multilateral agreement for
cross-border legal cooperation, including evidence requests. Processing time
varies from months to years.

**[NAR](https://nixos.org/manual/nix/stable/store/file-system-object/content-address.html)**
— Nix Archive. Canonical binary serialization of a Nix store path, used as the
input to content-addressing. The NAR hash of a path must match its declaration;
mismatch fails the build.

**[nix2container](https://github.com/nlewo/nix2container)** — Tool that produces
OCI images from Nix store paths, mapping each path to a content-addressed layer
to maximize cache reuse.

**[NSL](https://www.eff.org/issues/national-security-letters)** — National
Security Letter. Administrative subpoena issued by the FBI without judicial
review. Carries a statutory gag order: the recipient cannot disclose that the
letter was received.

**[OCI](https://opencontainers.org/)** — Open Container Initiative. Industry
standards for container image format, distribution, and runtime.

**[OIDC](https://openid.net/connect/)** — OpenID Connect. Identity layer on
OAuth 2.0. Used here for keyless signing: a CI platform issues a short-lived
OIDC token asserting the workflow identity, which cosign uses as the signing
credential.

**[P-256](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-5.pdf)** — NIST
P-256 elliptic curve (secp256r1). Used in ECDSA. NIST-standardized and widely
deployed; treat as potentially weakened given the Dual_EC_DRBG precedent.

**[PRISM](https://en.wikipedia.org/wiki/PRISM)** — NSA program for collection of
stored internet communications directly from major US tech companies under FISA
Section 702 authority.

**[QUANTUM INSERT](https://en.wikipedia.org/wiki/QUANTUM_INSERT)** — NSA/GCHQ
technique for injecting malicious content into HTTP streams via a
man-on-the-side attack. The attacker races the legitimate server response with a
crafted packet.

**[Rekor](https://github.com/sigstore/rekor)** — Sigstore's immutable,
append-only transparency log for software supply chain attestations. Entries are
publicly verifiable; the log is operated by the Sigstore project.

**[Sigstore](https://sigstore.dev/)** — Open-source project providing
infrastructure for signing, transparency, and verification of software
artifacts. Comprises cosign, Rekor, and Fulcio.

**[SLSA](https://slsa.dev/)** — Supply-chain Levels for Software Artifacts.
Framework defining levels of supply chain integrity guarantees, from basic
provenance (L1) to hermetic, reproducible builds (L4).

**[TAO](https://en.wikipedia.org/wiki/Tailored_Access_Operations)** — Tailored
Access Operations. NSA division responsible for active exploitation of foreign
targets, including hardware implants and network-level attacks.

**[UPSTREAM](https://en.wikipedia.org/wiki/UPSTREAM_collection)** — NSA program
for bulk collection of internet traffic at the backbone level under FISA Section
702, operating at major fiber and switching infrastructure.
