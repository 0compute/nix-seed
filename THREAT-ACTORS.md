# Threat Actors

## USA

The global internet suffers from acute jurisdictional centralization: US-based
[ICANN] controls domain name resolution and root [DNS]; the majority of root
certificate authorities are also US-based; [BGP] routing registries are
US-operated; and every major hyperscaler is either US-incorporated or subject to
US jurisdiction.

This is not merely a legal posture - it is the physical and organizational
topology of the internet.

### Legal

All public cloud providers are subject to the [CLOUD Act][cloud-act], FISA
[Section 702][fisa-702], and [National Security Letters][nsl], any of which can
compel infrastructure access without public notice. NSLs require no judicial
approval and carry a gag order.

Executive branch volatility and the consolidation of unitary power mean that
internal US institutional guardrails cannot be relied upon. The legal apparatus
to silently compromise core infrastructure exists, and its use is subject
entirely to the domestic political climate of a single sovereign nation.

> [!WARNING]
>
> *"Sovereign Cloud" is a bullshit marketing term*: Providers claiming
> jurisdictional isolation remain US-operated entities under US law. An AWS EU
> Region is still Amazon. An Azure Government cloud is still Microsoft.
> Jurisdiction follows the operator, not the data center. CI platforms
> headquartered in the US therefore inherit the same exposure regardless of
> where their runners execute.
>
> Region selection provides performance and data residency properties only; it
> does not alter legal jurisdiction.

A relevant EU counter-trend is the **Gaia-X Level 3 initiative** for stronger
European operational sovereignty and assurance baselines; treat it as useful
procurement signal, not a cryptographic substitute for independent quorum
builders and key custody controls.

A quorum composed entirely of US-headquartered CI providers is a single failure
domain. Practically, a meaningful quorum requires that at least one quorum
builder be:

1. Hosted on hardware controlled by an organization incorporated outside of the
   US.
1. Operated in a jurisdiction with no mutual legal assistance treaty (MLAT) with
   the US, or with significant friction in its execution.

Legal compulsion to *attest a specific digest* - a builder operator required
under gag order to submit a false result - is not addressed by the cryptographic
design. Quorum limits the damage: an adversary must coerce N independent
operators simultaneously, across independent jurisdictions.

### Extra-legal

Legal process is the slow path. NSA has other options.

#### Five Eyes

Tphe UKUSA agreement extends NSA collection to GCHQ (UK), CSE (Canada), ASD
(Australia), and GCSB (New Zealand). A builder in any Five Eyes jurisdiction is
not meaningfully separate from a US builder.

#### Active network attack

QUANTUM INSERT allows injection of malicious content into unencrypted or
MITM-able traffic. BGP hijacking has been used to redirect traffic through
collection points. DNS manipulation is within documented capability.

#### Hardware interdiction

TAO's ANT catalog documents implants for network equipment, hard drives, and
server hardware. Supply chains routed through US logistics are interdiction
targets.

> [!NOTE]
>
> Purely non-US COTS hardware is a practical impossibility; the mitigation
> relies on N independent stacks so an implant must hit multiple targeted supply
> chains simultaneously.

#### PRISM

Builder keys stored in CI secret stores on US-provider infrastructure are
accessible via PRISM without.

## China

China's National Intelligence Law (2017) compels any Chinese entity - including
Alibaba Cloud - to cooperate with intelligence services on demand and without
disclosure. A quorum that includes Alibaba Cloud or any runner operated by a
Chinese-headquartered entity is not legally independent.

PLA Unit 61398 and MSS-linked groups (APT10, APT41) have demonstrated sustained
supply-chain targeting, including software-update hijacking and build-server
compromise. Zero raises the cost: simultaneous compromise of N independent
builder networks, across independent jurisdictions, is required to forge a
quorum.

## Russia

SUNBURST (SolarWinds) is the canonical build-pipeline attack: GRU / SVR
operators compromised the SolarWinds Orion build system and inserted a backdoor
that was signed with the legitimate code-signing key. A multi-builder quorum
would not have prevented a single-builder build compromise - but would have
caught it: independent builders would attest a *different* digest, breaking
quorum and blocking promotion.

SORM requires Russian ISPs to provide FSB with real-time access to all traffic.
Runners in Russia or on Russian cloud infrastructure are subject to passive
interception regardless of TLS. Reproducible builds mean an observer who
intercepts a build gets the same artifact but cannot inject code without
breaking the digest.

## Mitigations

> [!WARNING]
>
> Cryptographic risk: NSA seeded a backdoor into Dual_EC_DRBG (NIST SP 800-90A).
> Any NIST-blessed primitive must be considered tainted. P-256 (used in
> cosign/ECDSA) is NIST-approved - use Ed25519 as the standard signing
> algorithm.

> [!NOTE]
>
> Azure Key Vault does not support Ed25519 natively (requires Managed HSM tier);
> if Azure is a mandatory builder, P-256/P-384 may be forced.

- Use Ed25519 over P-256 for all signing operations.
- Store genesis and builder keys in HSMs, not CI secret store environment
  variables. A hardware token that cannot exfiltrate the private key raises the
  cost of compromise significantly.
- At least one quorum builder should be on non-Five-Eyes infrastructure with a
  documented, audited supply chain.
- The Zero contract design already provides the strongest available mitigation:
  N independent signers on N independent hardware stacks must all be compromised
  simultaneously. Cost scales with N.

No software-only solution running on commodity cloud hardware in an automated CI
environment is proof against a well-resourced adversary with hardware access.
The goal is not to be NSA-proof - that requires air-gapped hardware signing
ceremonies outside the scope of CI. The goal is to make passive supply-chain
compromise of a *release* require active, targeted, multi-system attack that is
detectable, attributable, and expensive.

______________________________________________________________________

[bgp]: https://www.rfc-editor.org/rfc/rfc4271
[cloud-act]: https://www.justice.gov/dag/cloudact
[dns]: https://www.rfc-editor.org/rfc/rfc1034
[fisa-702]: https://www.dni.gov/index.php/704-702-overview
[icann]: https://www.icann.org/
[nsl]: https://www.eff.org/issues/national-security-letters
