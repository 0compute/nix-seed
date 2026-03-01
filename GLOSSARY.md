# Glossary

**Anchor:** Writing a release fingerprint (digest or Merkle root) to an
immutable ledger so it cannot be silently changed later.

**[ANT catalog](https://en.wikipedia.org/wiki/ANT_catalog):** NSA's classified
menu of hardware and software implants for targeted surveillance, leaked by
Snowden in 2013. Documents implants for network equipment, hard drives, and
server firmware.

**[Attestation](https://slsa.dev/attestation-model):** A verifiable record that
a specific build occurred from specified inputs by a known builder. See also:
in-toto, Rekor, OIDC, Registry.

**[BGP](https://www.rfc-editor.org/rfc/rfc4271):** Border Gateway Protocol (RFC
4271). The routing protocol that directs traffic between autonomous systems on
the internet. BGP hijacking redirects traffic through an adversary-controlled
network path.

**Builder:** A machine or CI runner that performs a build and submits evidence
(attestations).

**[calldata](https://ethereum.org/en/developers/docs/transactions/):** The input
data payload of an Ethereum transaction. See also: Gas.

**[CDN](https://en.wikipedia.org/wiki/Content_delivery_network):** Content
Delivery Network. A geographically distributed network of proxy servers that
cache and serve content to end users from nearby nodes. Major CDN operators
(Cloudflare, Fastly, Akamai) are US-incorporated or subject to US jurisdiction.

**[CI](https://en.wikipedia.org/wiki/Continuous_integration):** Continuous
Integration. The practice of automating the integration of code changes from
multiple contributors into a single software project.

**[Closure](https://nix.dev/manual/nix/stable/glossary#gloss-closure):** The
full transitive set of store paths required by a Nix derivation, including all
dependencies and their dependencies recursively. Packaging the closure as OCI
layers is the core mechanism of Nix Seed.

**[CLOUD Act](https://www.justice.gov/dag/cloudact):** Clarifying Lawful
Overseas Use of Data Act (2018). Requires US-operated providers to produce data
stored abroad when served with a US warrant, regardless of physical location.

**[cosign](https://docs.sigstore.dev/cosign/overview/):** Sigstore tool for
signing, verifying, and storing signatures and attestations in OCI registries.

**[COTS](https://en.wikipedia.org/wiki/Commercial_off-the-shelf):** Commercial
Off-The-Shelf hardware or software purchased through normal commercial channels.
Relevant here because most server hardware passes through US logistics channels
regardless of operator jurisdiction, making it a target for supply-chain
interdiction.

**[DNS](https://www.rfc-editor.org/rfc/rfc1034):** Domain Name System. The
global hierarchical naming system that translates human-readable domain names to
IP addresses.

**[Dual_EC_DRBG](https://en.wikipedia.org/wiki/Dual_EC_DRBG):** Dual Elliptic
Curve Deterministic Random Bit Generator. A NIST-standardized PRNG (SP 800-90A)
subsequently confirmed to contain an NSA-planted backdoor.

**[Ed25519](https://ed25519.cr.yp.to/):** Edwards-curve Digital Signature
Algorithm over Curve25519. Not NIST-standardized. Preferred over P-256.

**[FISA Section 702](https://www.dni.gov/index.php/704-702-overview):** Foreign
Intelligence Surveillance Act Section 702. Authorizes warrantless collection of
communications of non-US persons from US-based providers.

**[Five Eyes](https://en.wikipedia.org/wiki/Five_Eyes):** UKUSA signals
intelligence alliance: United States (NSA), United Kingdom (GCHQ), Canada (CSE),
Australia (ASD), New Zealand (GCSB). Intelligence collected by any member is
shared across all.

**[Gas](https://ethereum.org/en/developers/docs/gas/):** The unit used to
measure computational work on EVM-compatible chains. Transaction fee is gas used
times gas price. Used on Ethereum L2.

**[HSM](https://en.wikipedia.org/wiki/Hardware_security_module):** Hardware
Security Module. Tamper-resistant hardware device for cryptographic key storage
and operations. Private keys cannot be exported; signing occurs inside the
device.

**[HUMINT](<https://en.wikipedia.org/wiki/Human_intelligence_(intelligence_gathering)>):**
Human Intelligence. Intelligence gathered through interpersonal contact:
recruitment, social engineering, or insider threats. Technical controls do not
address HUMINT; key ceremony discipline and HSM-resident keys limit insider
blast radius.

**[ICANN](https://www.icann.org/):** Internet Corporation for Assigned Names and
Numbers. US-incorporated nonprofit that administers the global DNS root zone, IP
address allocation, and protocol parameter registries. Structural US control
over the DNS root is independent of any specific administration.

**[in-toto](https://in-toto.io/):** Framework for securing software supply
chains by defining and verifying each step in a build pipeline via signed link
metadata.

**KMS:** Key Management Service. A managed system used to store cryptographic
keys and perform signing operations without exposing private key material to
build scripts. See
[NIST SP 800-57](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final) for key
management recommendations.

**[L2](https://ethereum.org/en/layer-2/):** Ethereum Layer 2. A network that
records transactions and ultimately settles them to Ethereum (L1). In this
design, it is used as an immutable public ledger for release anchors.

**[Merkle root](https://en.wikipedia.org/wiki/Merkle_tree):** A single digest
that summarizes a tree of digests and allows efficient inclusion proofs for each
leaf.

**[MLAT](https://en.wikipedia.org/wiki/Mutual_legal_assistance_treaty):** Mutual
Legal Assistance Treaty. Bilateral or multilateral agreement for cross-border
legal cooperation, including evidence requests. Processing time varies from
months to years.

**[Multi-sig](https://en.wikipedia.org/wiki/Threshold_cryptosystem):**
Multi-signature scheme requiring M-of-N keyholders to co-sign an operation. Used
here for governance (builder key rotation and revocation) to prevent unilateral
control. See also: N-of-M.

**N-of-M:** Out of `M` configured builders, at least `N` independent builders
must report the same result.

**[NAR](https://nix.dev/manual/nix/stable/glossary):** Nix Archive. Canonical
binary serialization of a Nix store path, used as the input to
content-addressing. The NAR digest of a path must match its declaration;
mismatch fails the build.

**[narinfo](https://nix.dev/manual/nix/stable/package-management/binary-cache-substituter):**
Metadata file in a Nix binary cache describing a store path: its NAR digest,
references, deriver, and optional signature. Fetched by a substituter before
downloading the NAR archive.

**[National Intelligence Law (2017)](https://www.chinalawtranslate.com/en/national-intelligence-law/):**
Chinese law compelling any Chinese entity to cooperate with intelligence
services on demand and without public disclosure.

**[NSL](https://www.eff.org/issues/national-security-letters):** National
Security Letter. Administrative subpoena issued without judicial review. Carries
a statutory gag order: the recipient cannot disclose that the letter was
received.

**[OAuth 2.0](https://www.rfc-editor.org/rfc/rfc6749):** Open Authorization
framework (RFC 6749) for delegated authorization without exposing credentials.
The basis for OIDC identity assertions used in keyless signing.

**[OCI](https://opencontainers.org/):** Open Container Initiative. Industry
standards for container image format, distribution, and runtime.

**[OIDC](https://openid.net/connect/):** OpenID Connect. Identity layer on OAuth
2.0. Used here for keyless signing: a CI platform issues a short-lived OIDC
token asserting the workflow identity, which cosign uses as the signing
credential.

**[OpenTelemetry](https://opentelemetry.io/):** Vendor-neutral observability
framework for collecting traces, metrics, and logs. Used here to instrument CI
job phases (seed pull, mount, build) with structured spans for timing analysis.

**[P-256](https://csrc.nist.gov/pubs/fips/186/5/final):** NIST P-256 elliptic
curve (secp256r1), defined in FIPS 186-5. Used in ECDSA. NIST-standardized and
widely deployed; treat as potentially weakened given the Dual_EC_DRBG precedent.

**[PRISM](https://en.wikipedia.org/wiki/PRISM):** NSA program for collection of
stored internet communications directly from major US tech companies under FISA
Section 702 authority.

**[QUANTUM INSERT](https://en.wikipedia.org/wiki/QUANTUM_INSERT):** NSA/GCHQ
technique for injecting malicious content into HTTP streams via a
man-on-the-side attack. The attacker races the legitimate server response with a
crafted packet.

**[Registry](https://github.com/opencontainers/distribution-spec):** An
OCI-compliant service for storing and distributing container images and
artifacts. Addressed by content digest (immutable) or by tag (mutable). In this
design, registry tags are non-authoritative; the image digest is the release
pointer.

**[Rekor](https://github.com/sigstore/rekor):** Sigstore's immutable,
append-only transparency log for software supply chain attestations. Entries are
publicly verifiable; the log is operated by the Sigstore project.

**Ephemeral runner:** Executes CI job steps. Runners start fresh on every job
with no persistent state.

**[sigstore](https://sigstore.dev/):** Open-source project providing
infrastructure for signing, transparency, and verification of software
artifacts. Comprises cosign, Rekor, and Fulcio.

**[SLA](https://en.wikipedia.org/wiki/Service-level_agreement):** Service Level
Agreement. A contractual commitment on availability, reliability, and support
response time. Rekor (Sigstore's transparency log) carries no enterprise SLA; an
outage blocks attestation in Dev mode.

**[SORM](https://en.wikipedia.org/wiki/SORM):** Sistema Operativno-Rozysknikh
Meropriyatiy (System for Operative Investigative Activities). Russian federal
law requiring telecommunications operators to install equipment providing FSB
with real-time access to all communications traffic, without a warrant.

**[Substituter](https://nix.dev/manual/nix/stable/command-ref/conf-file#conf-substituters):**
A Nix binary cache endpoint. When enabled, Nix fetches pre-built store paths
from the substituter instead of building locally from source. See also: NAR.

**[SUNBURST](https://en.wikipedia.org/wiki/2020_United_States_federal_government_data_breach):**
The SolarWinds supply chain attack (2020). GRU/SVR operators compromised the
SolarWinds Orion build system and inserted a backdoor signed with the legitimate
code-signing key, affecting thousands of organizations including US federal
agencies.

**[TAO](https://en.wikipedia.org/wiki/Tailored_Access_Operations):** Tailored
Access Operations. NSA division responsible for active exploitation of foreign
targets, including hardware implants and network-level attacks.

**[TLS](https://www.rfc-editor.org/rfc/rfc8446):** Transport Layer Security (RFC
8446). Cryptographic protocol that encrypts network traffic between two parties.
Protects against passive eavesdropping but not against a provider compelled to
cooperate or a network-level man-on-the-side attacker (see QUANTUM INSERT).

**[Trusting Trust](https://dl.acm.org/doi/10.1145/358198.358210):** Ken
Thomson's seminal attack: a compiler can be modified to insert a backdoor into
programs it compiles, including a modified copy of itself into compilers it
compiles, making the backdoor invisible in source. Defeated by bootstrapping the
compiler chain from a human-auditable binary seed rather than an opaque binary.
