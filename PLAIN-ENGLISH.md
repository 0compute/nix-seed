# Nix Seed: Plain English

## The Velocity Problem

Engineers store source code in *Git* - a system that records every change, who
made it, and when. The history is permanent and public. When an engineer
*pushes* a change - uploads it to Git - an automated system runs a *build* on a
remote server.

The build compiles source code - the human-readable instructions - into *machine
code*: the binary instructions a processor executes directly. Processors are not
all alike; an ARM chip (common in Android and Apple devices) and an x86 chip
(common in Intel/AMD servers) speak different machine code dialects. A program
compiled for one *architecture* will not run on the other, so builds run
separately on each target.

Before the build can begin, *dependencies* - the libraries and tools the program
relies on - must be fetched and/or built themselves. Without Nix Seed, this
happens on every run, every time, regardless of whether those dependencies have
changed.

Three costs:

1. **Time.** The engineer waits.
1. **Focus.** The wait breaks concentration. Regaining full focus after an
   interruption takes time - often longer than the interruption itself.
1. **Compute.** The same setup cost - cash and energy - is paid repeatedly.

## The Velocity Solution

Nix Seed pre-builds the dependencies and stores them in a *registry* - a
software warehouse.

The dependencies are packaged as *layers*: self-contained bundles, each
identified by a fingerprint of its exact contents. When a build starts, the
builder fetches the layers it needs - already built, already verified - and the
build begins. No compilation. No fetching from dozens of upstream sources. The
build starts in seconds.

The registry itself does not need to be trusted. Before a layer is used, its
digest is verified locally - the fingerprint of the downloaded content must
match exactly what was declared. A tampered or compromised registry cannot
serve a malicious layer undetected: the digest will not match, and the build
will fail. Trust is in the math, not the service.

Registry location matters. Fetching layers across the internet from a distant
server adds latency. The registry should be co-located with the CI provider -
on the same network, ideally in the same data centre - so that layer transfers
are fast local hops rather than round trips across the open internet.

## The Security Problem

Pre-built packages are convenient. They are also a target.

If an attacker tampers with the pre-built package, every program built from it
is compromised - and nobody knows. This is a *supply chain attack*. In 2020,
attackers did exactly this to a widely-used IT product, compromising thousands
of organisations including US government agencies. The tampered software was
signed with the legitimate key, so every security check passed.

## The Security Solution

Nix Seed addresses this with mathematical fingerprints. Every package is
identified by a digest computed from its exact contents. If a single byte
changes, the digest changes. If the package does not match, the build fails.

Nix Seed also produces two records alongside every build:

- A *cryptographic signature* - a mathematical seal on the build output.
  Produced with a private key held by the builder; anyone with the corresponding
  public key can verify it. If the output or signature has been tampered with,
  verification fails.
- A *provenance record* - a signed statement of what was built, from what
  source, by which builder, and when. A verifier can confirm that a given binary
  came from a specific Git commit built by a specific builder.
- An *SBOM* (Software Bill of Materials) - a complete ingredient list of every
  library and tool that went into the build. Like a food label for software:
  every component declared, every version recorded.

## The Compiler Problem

There is a deeper issue. Source code is compiled by a *compiler* - another
program. If the compiler itself has been secretly modified, it can insert a
*backdoor* - hidden code that gives an attacker secret access to any system
running the program - into itself and every program built from it. You cannot
see the backdoor in the source code. You cannot see it in the output. It is
invisible to any review.

This is not theoretical. Ken Thomson, co-creator of Unix,
[demonstrated it in 1984](https://dl.acm.org/doi/10.1145/358198.358210): a
compiler modified to plant a backdoor in login programs, and to plant itself
into any new compiler it compiles - making the attack self-perpetuating across
generations of software.

## The Compiler Solution

*Full-Source Bootstrap*: Build the entire compiler chain from scratch, starting
from a tiny program small enough for a human to read and verify by hand. No
pre-compiled binary is trusted. Every tool in the chain is built from auditable
source.

## The Trust Problem

Who created the fingerprint, and can they be trusted?

## The Trust Solution

### Trust Level: Innocent

One server builds the package and records the fingerprint on a *public log* - a
tamper-evident, publicly accessible record of build events.

- **Guarantees:** Tampering after the record is detectable.
- **Does not cover:** The builder, log service, and package cache are all
  subject to US law. The US government can compel any of them.
- **Cost:** Free.

### Trust Level: Credulous

Multiple independent servers across different organisations and countries each
build the package. A *Master Builder* - a designated coordinator server - signs
off only when a *quorum* - a minimum number of independent builders - agree on
the result.

- **Guarantees:** An attacker must compromise multiple independent organisations
  simultaneously.
- **Does not cover:** The Master Builder and log service are still single points
  of control. Both are capturable.
- **Cost:** Free.

### Trust Level: Zero

A *blockchain* is a shared record book maintained simultaneously by thousands
of servers worldwide. No single server owns it. Every entry is permanent:
nothing can be changed or deleted without the agreement of more than half the
network. Because no single party controls it, no single party can tamper with it.

Release rules are encoded in a *smart contract* on a public blockchain - a
program stored on the blockchain that runs automatically and cannot be
overridden. The contract enforces that a minimum number of independent builders
must agree on the result. No person, company, or government can change the
rules or approve a release outside of them.

- **Guarantees:** Rules enforced by mathematics, not by trust. See [Four
  Pillars](#four-pillars) below. A compromised builder cannot inject silently
  - it must produce the same output as every other builder, which forces any
  backdoor into the public source repository.
- **Remaining risks:** Hardware tampered with before delivery. Configuration
  mistakes. Governance keys.
- **Cost:** ~$3-9 per release.

#### Four Pillars

Four properties make this guarantee hold:

- *Full-Source Bootstrap.* The compiler chain is built from scratch from
  human-auditable source. No pre-compiled binary is trusted.
- *Contract-Enforced Builder Independence.* The smart contract requires
  builders to be from genuinely separate organisations and jurisdictions. One
  party cannot control multiple "independent" builders to fake a quorum.
- *No Central Actor.* No single entity - no Master Builder, no log service -
  can unilaterally approve a release. The contract replaces them all.
- *Immutable Ledger.* The blockchain record cannot be altered or deleted.
  A tampered release cannot be quietly erased.

> [Trust Level Zero](#trust-level-zero) is not yet implemented. Funding
> applications are pending.

## The Binary Cache Problem

Compiling software from source is slow. To avoid repeating work, builds often
pull pre-compiled packages from a *binary cache* - a server that stores
ready-made results. If the package is already in the cache, it is downloaded
instead of built.

If two quorum builders both pull from the same binary cache, they are not
building independently - they are both trusting the cache operator. If the
cache is compromised, both builders attest the same malicious output. Quorum
reaches agreement, but on tainted software.

## The Binary Cache Solution

In [Trust Level Zero](#trust-level-zero), each builder must build its entire
*closure* - the full set of dependencies, resolved and built from source - with
binary caches disabled. The build configuration is included in the
*attestation* - a signed record of what was built, by whom, and from what
inputs; a verifier can reject any build that used a shared cache.

## The Shared Cloud Infrastructure Problem

Even when builders are in separate organisations and jurisdictions, they can be
secretly coupled through the provider's own stack.

When you run a build on a cloud CI platform, you are not simply renting a
server. The platform controls the entire environment: it issues the
cryptographic credentials that prove the build happened, manages the signing
keys, routes all network traffic, and stores secrets. The platform operator can
see - and compel - all of it.

### Identity

Before a build result can be signed, the builder must prove its identity. Cloud
CI platforms issue short-lived cryptographic tokens for this purpose - digital
passports. GitHub Actions and Azure Pipelines both issue these tokens through
Microsoft-controlled infrastructure. Two builders on these platforms share the
same passport office: one order to Microsoft produces false credentials for
both, regardless of the organisations running them.

### Signing Keys

Builder signing keys are stored in the cloud provider's secret management
service. GitHub Secrets and Azure Key Vault are both Microsoft-operated. A key
held in a provider's secret store is accessible to that provider.

### Compute

Cloud builders do not run on dedicated hardware. Multiple customers' workloads
share the same physical machines, separated only by the provider's
virtualization layer. The provider controls that layer: it can inspect memory,
snapshot a running build, or redirect execution. Two builders sharing the same
physical hardware share a trust boundary.

A quorum of builders all running on the same provider's infrastructure - even
across different customer accounts and organisations - is not independent.

## The Shared Cloud Infrastructure Solution

Builder independence requires separation at every layer: separate identity
providers, separate key stores, and separate physical hardware. Builders sharing
any one of these with another builder do not satisfy
[Trust Level Zero](#trust-level-zero)'s independence requirement.

## The Nation State Problem

Any jurisdiction with legal authority over a builder can compel it to act
without public notice.

### US

The organizations that run the internet's core services (domain name resolution,
root certificate authorities, major cloud platforms, content delivery networks
that cache and serve web traffic globally) are predominantly US-incorporated or
subject to US law.

This is not merely a legal posture - it is how the internet is physically
built.

US law gives US government actors tools to compel any of these services without
public notice: the CLOUD Act requires US-operated providers to produce data on
request including data held abroad; FISA Section 702 authorizes collection
without a warrant; National Security Letters require no judicial approval and
carry a gag order - the recipient cannot disclose that a request was made.

> [!NOTE]
>
> **"Sovereign Cloud" is a bullshit marketing term.** Providers claiming
> jurisdictional isolation remain US-operated entities under US law. An AWS EU
> region is still Amazon. An Azure Government cloud is still Microsoft.
> Jurisdiction follows the operator, not the data centre. Region selection
> provides performance and data residency (where your data is physically stored)
> properties only - it does not change who controls the service or who can be
> compelled to hand over access.

The Five Eyes alliance (US, UK, Canada, Australia, New Zealand) extends this:
intelligence collected by any member is shared across all.

### China

The National Intelligence Law (2017) compels any Chinese entity to cooperate
with state intelligence services on demand and without disclosure. An
organisation incorporated in China - including Alibaba Cloud - cannot refuse.

### Russia

SORM requires all telecommunications operators to give security services
real-time access to all traffic without a warrant. The 2020 supply chain
attack [referenced above](#the-security-problem) was a Russian state
operation: attackers compromised the SolarWinds Orion build pipeline and
signed the backdoor with the legitimate key. It passed every check because
there was only one build to compromise.

A quorum confined to any single jurisdiction - or to jurisdictions bound by
intelligence-sharing agreements - is a single legal target.

## The Nation State Solution

A credible quorum must span genuinely independent jurisdictions. Each builder
must be incorporated and operated in a distinct jurisdiction, with no
intelligence-sharing relationship to the others.

[Trust Level Zero](#trust-level-zero) enforces this in the smart contract:
builders declare their organisation and jurisdiction, and the contract verifies
independence before counting any attestation toward quorum. No single
jurisdiction can satisfy the quorum requirement alone, regardless of how many
builders it controls.

Passive interception is also addressed: builds are reproducible. An observer
who intercepts a build in transit gets the same artifact every other builder
produced. They cannot inject code without changing the output - which changes
the digest - which breaks quorum.

## The Hardware Problem

Every software guarantee rests on hardware that can be tampered with before it
arrives.

Intelligence agencies have documented implants for network equipment, hard
drives, and server hardware, inserted during manufacture or transit. A
compromised machine can produce false attestations that pass every software
check.

## The Hardware Solution

No software-only system fully addresses hardware compromise. The mitigation is
to require N independent hardware supply chains: an attacker must implant
hardware across N separate, targeted supply chains simultaneously. The cost and
risk of detection scale with N. Quorum does not eliminate the threat - it
raises its price.

## The Trust Limit

Nix Seed proves that what is in Git is exactly what was built. It does not
audit what is in Git.

If an engineer merges a malicious update - through compromise, deception, or
error - Nix Seed will faithfully build, sign, and *anchor* - record permanently
on the blockchain - the result. The cryptographic guarantees hold. The result is
simply well-attested malware. Human review of dependency changes remains a
critical security boundary that no automated system replaces.

## Summary

| | [Innocent](#trust-level-innocent) | [Credulous](#trust-level-credulous) | [Zero](#trust-level-zero) |
|---|---|---|---|
| Build starts in seconds | Yes | Yes | Yes |
| Single point of failure | Yes | Yes | No |
| Resistant to high-level threat actors | No | No | Yes |
| Cost | Free | Free | ~$3-9 per release |
