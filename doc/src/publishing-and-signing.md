# Publishing and Signing

The `.#publish` app is responsible for pushing the built Seed images to a
container registry and ensuring they are cryptographically signed and attested.

## Keyless Signing with Cosign

Nix Seed uses **Keyless Signing** via
[cosign](https://github.com/sigstore/cosign). This approach eliminates the need
for managing and securing private keys.

- **Identity-based**: When running in GitHub Actions, `cosign` uses the runner's
  OIDC (OpenID Connect) token to prove identity.
- **Experimental Mode**: The environment variable `COSIGN_EXPERIMENTAL: '1'` is
  set to enable this flow.

## Rekor Transparency Log

Every signature and attestation is recorded in
[Rekor](https://rekor.sigstore.dev), a public transparency log.

- **Verifiability**: This creates an immutable, append-only record linking the
  builder's identity (e.g., a specific GitHub workflow) to the container image
  digest.
- **Auditability**: Downstream consumers can verify the proof chain without
  needing to pull the entire image.

## The Attestation Flow

The publishing process includes a critical "attest" phase:

1. **Predicate Generation**: A JSON predicate is generated containing metadata
   such as the `narHash`, `commit` SHA, and `builder` identity.
1. **Cosign Attest**: The `cosign attest` command is used to sign the predicate
   and push it to the registry as an OCI artifact attached to the image.
1. **Rekor Logging**: The signature is simultaneously logged to Rekor.

### Example Command \`\`\`bash cosign attest \\ --rekor-url https://rekor.sigstore.dev \\

--type https://github.com/roundtablelove/nix-seed \\ --predicate
"./$commit.$system.json" \
"$image" \`\`\`

## Verification You can use the `verify` application (provided in the flake) to check

these signatures: `bash nix run .#verify -- <image_name>:<tag> ` This ensures
that the image in the registry exactly matches the one described in the Rekor
transparency log.
