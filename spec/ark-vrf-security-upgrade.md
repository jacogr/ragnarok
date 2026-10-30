# ark-vrf 0.6.1 security qualification

The maintained primitive dependency advances from ark-vrf 0.6.0
`dfb696dfb92425009af80dbbb403e647f6c9e3e4` to
[`cf1dbbb260ec3e7ea88eac68148f05d5cbd587ac`](https://github.com/davxy/ark-vrf/releases/tag/v0.6.1).
The reviewed lock advances only ark-vrf, w3f-ring-proof 0.0.10 to 0.0.11 and its
w3f-plonk-common 0.0.11 dependency. The pinned Rust 1.99 toolchain exceeds the
updated upstream Rust 1.90 minimum.

The release binds each ring batch verifier's KZG randomizer to every proof in
the batch. Its previous per-proof binding permitted an attacker controlling a
batch to arrange cancellation between invalid proofs. This is an upstream batch
verification fix; single-proof verification, Thin/Pedersen batch verification,
keys, commitments and proof encodings are unchanged.

Ragnarok's maintained `bs_ring_verify` ABI verifies one proof through
`RingProof::verify`. It exposes no batch-verification entry point. The two-worker
offload queue invokes that individual primitive; concurrent queued jobs are not
one algebraic batch. No currently exposed attack path through that batch API is
claimed. Updating the locked closure keeps future use from inheriting the known
batch weakness while preserving the present primitive boundary.

## Preserved protocol profile

The adopted Gray Paper, Draft 35 source, v1 suite, sixteen-byte challenge, 96/784-byte
ABI, transcript/nonce separation, canonical/subgroup/identity checks, Z_pad,
public Zcash SRS and requested-capacity domain policy remain unchanged.
Draft 36 clarifies the existing v1 padding deviation; its later reference ring
vectors use a 2048 domain even for eight keys. That does not authorize changing
Ragnarok's existing requested-capacity domains or selecting `bandersnatch_v2`.
The pinned Draft 35 vectors and historical incompatible-profile evidence remain
distinct. No insecure deterministic/non-ZK vector feature is enabled.

Both primitive manifests record the new lock digest. The six frozen JAM input
witnesses bind the complete Bandersnatch pin file, so their provenance digest and
dependent reports/descriptors must be refreshed together. Their keys, tickets,
commitments, normalized members, cryptographic values and state results are
preserved byte for byte. Official JAM vector source identities and historical signed-trace
qualifications are unchanged.

Qualification uses the existing independent Thin mathematical reference,
native Thin/ring and invalid-input ABI corpus, owner/refusal checks, and
contextual/Safrole consumers. Frozen provenance checks precede full CI on the
top stack layer. These tests retain the existing parity boundaries; dependency
upgrading and vector success are not an independent cryptographic audit.
