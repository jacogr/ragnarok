# Verified partial state reads

A `ProofView` retains verified facts about selected serialized state keys under one
independently trusted root. It holds three different outcomes: a key can be present
(including an empty value), proven absent, or unknown because no witness was supplied.
`lookup` returns `MissingWitness` for unknown keys. Never treat that as absence.

Use `verifyStateProofs` to authenticate raw query witnesses, then `captureProofView`
with your trusted root and explicit count/value-byte ceilings. Capture sorts exact
keys and rejects duplicates or foreign roots. An empty view is valid evidence about
zero keys; it does not represent an empty complete state.

`mergeProofViews` combines facts only under the same root and coalesces identical
keys. It checks unique output counts/bytes and rejects conflicting evidence.
`projectProofView` retains an explicitly requested subset; missing keys and duplicate
requests refuse. Every operation publishes a new immutable owner and leaves its
sources unchanged. Returned byte sequences and exported query records are detached.

`exportProofQueries` supplies immutable raw witnesses for another consumer to verify
under its own root. Local RPV1 encoding carries sorted unique 31-byte keys and
E4-length-prefixed RSP1 witnesses, after its `RPV1` magic and E4 record count. It
carries no root authority. `decodeProofView` requires an independently supplied root,
individual proof limits, batch limits, view limits and outer byte ceiling. It checks
all framing and budgets before atomic authentication; suffixes, unknown versions,
unsorted/duplicate keys and later invalid proofs return no partial view.

`readProofTime` shows a typed read of authenticated C(11). It requires exactly four
bytes before delegating to the existing E4 state codec. Unknown C(11), proven absent
C(11) and malformed authenticated C(11) return different typed failures. A valid
Merkle proof does not certify state chronology or make malformed data canonical.

These interfaces do not create a light-node database, proof RPC, network protocol,
consensus trust or complete state snapshot. A partial view cannot be passed to
complete-map transition, root construction or checkpoint APIs. No operation derives
a replacement complete root from a partial collection.

See [the feature contract](../spec/state-proof-views.md) and
[underlying proofs](state-proofs.md) for pins, boundaries and reproduction. M1 framing
is complete; full state serialization and whole-block JAM/STF parity remain open.

Borrowed source maps and wire buffers must stay stable during synchronous calls.
The decoder checks remaining aggregate node/value allowances from each inner header
before copying that witness, while the outer byte/count ceilings bound parser scratch.
