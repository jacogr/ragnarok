# Cryptographic implementation instructions

- The current Gray Paper requires ZIP215 Ed25519 verification. Preserve its cofactored equation,
  noncanonical point acceptance and canonical scalar bound; no alternate-verifier fallback. Record
  intentional differences from RFC-labeled corpora in `spec/crypto-zip215-upgrade.md`.

For signing domains read [the protocol interpretations](../../spec/AGENTS.md) and the pinned
[domain audit](../../spec/signing-domains.md). Bandersnatch changes also require
[its primitive contract](../bandersnatch/AGENTS.md). Never infer an audit from passing vectors.
