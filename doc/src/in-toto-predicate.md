# In-toto Predicates

An **in-toto predicate** is the specialized metadata component of an
**Attestation**. In the in-toto specification, an attestation is a signed
statement that links a specific artifact (the **Subject**) to a set of facts or
claims (the **Predicate**).

To understand a predicate, you must look at the three-layered structure of an
attestation:

## 1. The Envelope (The "Who")

This is the outer layer (usually a DSSE envelope) that contains the signature.
It proves that a specific identity (e.g., a GitHub Actions OIDC identity) signed
the document.

## 2. The Statement (The "What")

The statement is the JSON body that binds the signature to the data. It
contains:

- **\_type**: Always `https://in-toto.io/Statement/v1`
- **subject**: A list of artifacts (name + digest) that this attestation is
  about.
- **predicateType**: A URI defining the schema of the metadata.
- **predicate**: The actual metadata object.

## 3. The Predicate (The "Facts")

The predicate is the "payload." It is the structured information that describes
*how* the artifact was made or *what* it contains. There are several standard
predicate types:

- **Provenance (SLSA)**: Describes the build process (which repo, which runner,
  which commands).
- **Vulnerability Scan**: Lists known CVEs at the time of build.
- **Test Results**: Records whether unit/functional tests passed.

______________________________________________________________________

### Example from Nix Seed

In the `publish` script, the predicate is a custom type tailored for Nix
reproducibility:

```json
{
  "schemaVersion": 1,
  "predicateType": "https://github.com/roundtablelove/nix-seed",
  "narHash": "sha256:123...",
  "closureManifest": "sha256:456...",
  "commit": "abcdef...",
  "system": "x86_64-linux",
  "builder": {
     "workflow": "seed.yaml",
     "actor": "arthur"
  }
}
```

### Why "in-toto"?

The name comes from the **in-toto framework**, which aims to provide "whole" (in
toto) security for the supply chain. By using this format, you ensure that your
build metadata is **interoperable**. Tools like `cosign`, `slsa-verifier`, and
policy engines can parse this JSON to verify your supply chain without needing
to understand the internals of your specific build script.
