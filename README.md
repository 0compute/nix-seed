# Nix Seed

Nix on ephemeral CI.

Source-only change: **build setup <10s**.

Dependencies via [OCI] layers.

Explicit trust anchors.

> Supply chain, secured: **$$$**.
>
> Dependencies realised, once: **$$$**.
>
> Flow state, uninterrupted: **Priceless**.

Docs → [Design](./DESIGN.md) / [Threat Actors](./THREAT-ACTORS.md) /
[Plain-English Overview](./PLAIN-ENGLISH.md).

---

## OCI Layers vs `actions/cache`

`actions/cache` operates by:

1. Downloading a monolithic archive.
1. Writing it to disk.
1. Extracting it sequentially.
1. Re-archiving and uploading post-job.

This means:

- High network/disk I/O.
- Serialisation bottlenecks.
- Full dataset copy on every job.
- Poor scaling with cache size.

OCI layers are content-addressed:

- Layer pulls are parallelised.
- Deduplication is automatic.
- Filesystems mount layered content without full extraction.
- Only changed layers are transferred.

Observed characteristics:

- **VM provisioning:** ~5s (fixed provider cost)
- **Layer pull + mount:** <5s (with runner-local registry, e.g. GHCR)
- **Source fetch:** unchanged
- **Build execution:** unchanged

---

## Trust

> **“Just because you're paranoid doesn't mean they aren't after you.”**
>
> — Anonymous, c. 1967

Nix Seed provides four trust modes. Choose one.

---

### Trust Level: Innocent

> **“IDGAF about trust. Gimme the Fast!”**
>
> — Every engineer ever born of woman

[Innocent](./DESIGN.md#innocent) anchors trust on the public-good Rekor
instance with a single builder.

- Guarantee: None.
- Attack Surface: Builder, Rekor, and Nix cache infrastructure — all central actors.
- Resiliency: Public-good Rekor publishes an availability SLO (not a contractual SLA); downtime can block logging and verification when depended on.
- Cost: Free.

---

### Trust Level: Credulous

> **“I Want To Believe.”**
>
> — Fox Mulder, The X-Files, 1993

[Credulous](./DESIGN.md#credulous) anchors trust on the public-good Rekor
instance with an N-of-M independent builder quorum (a defined N-of-M threshold).

Credulous assumes builders can fail independently, but treats transparency infrastructure as trusted.

When the configured builder quorum is reached, the Release Node creates a
signed git tag on the source commit.

- Guarantee: No single builder can forge a release; compromise requires quorum capture.
- Attack Surface: Builder set, Release Node, public-good Rekor, OIDC trust roots.
- Resiliency: As for [Innocent](#trust-level-innocent).
- Cost: Free.

---

### Trust Level: Suspicious

> **“Trust, but verify.”**
>
> — Ronald Reagan (Russian proverb), 1987

[Suspicious](./DESIGN.md#suspicious) keeps [Credulous](#trust-level-credulous)
builder quorum and adds a K-of-L transparency log quorum, recognising that
transparency infrastructure is itself a potential failure domain.

When quorum is reached, the Release Node signs and promotes the release.

- Guarantee: No single builder or single transparency log can unilaterally legitimise a release.
- Attack Surface: Builder set, Release Node, OIDC trust roots, transparency log operators.
- Resiliency: Higher availability than [Credulous](#trust-level-credulous); single-log outages are not automatically fatal.
- Cost: Moderate operational overhead for multi-log operation.

---

### Trust Level: Zero

> **“Ambition must be made to counteract ambition.”**
>
> — James Madison, *Federalist No. 51*, 1788
>
> **“Everyone has a plan until they get punched in the mouth.”**
>
> — Mike Tyson, 2002

[Zero](./DESIGN.md#zero) assumes that any actor may be compromised or coerced.

Validity is defined by quorum, not by authority.

Bitwise-identical output must be attested across independent failure domains
(separated across organisational, jurisdictional, and infrastructural boundaries).

Promotion occurs mechanically upon quorum verification.  
No Release Node exists; promotion is contract-enforced.

Forgery effort compounds with each additional independent failure domain.

Structure constrains power. Verification replaces trust.

- Guarantee: Contract-enforced quorum. Trust is anchored on an Ethereum L2 smart contract with an N-of-M independent builder quorum. Backing:
  - **Full-source bootstrap**
  - **Immutable ledger**
  - **Contract-enforced builder independence**
  - **No central actor**
- Attack Surface: Governance keys, misconfiguration,
  [hardware interdiction](./DESIGN.md#hardware-interdiction).
- Resiliency: High.
- Cost (3 builders, 4 systems): ~Ξ0.002 per promotion event (±50% depending on L2 gas conditions) (~$6 @ Ξ1=$3k).
