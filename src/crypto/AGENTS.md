# Cryptographic implementation instructions

- The exceptional-point Ed25519 acceptance policy is unresolved. Preserve actual backend verdicts
  and document the remaining gate; do not tune acceptance to make a corpus pass.

For signing domains read [the protocol interpretations](../../spec/AGENTS.md) and the pinned
[domain audit](../../spec/signing-domains.md). Bandersnatch changes also require
[its primitive contract](../bandersnatch/AGENTS.md). Never infer an audit from passing vectors.
