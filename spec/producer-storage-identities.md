# Producer-owned storage identities

Scope preserves Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. This adds opt-in execution evidence,
not protocol semantics, a supplied-delta API or a complete logical manifest.

A concrete consumer is automatic logical continuation when a real host write introduces a raw
storage key. Physical account-write hashes cannot recover that key. `AccumulationStorageFactLimits`
now admits first-touch raw identities at the successful storage operation, for both self and
supervised targets. Independent item, per-key and aggregate raw-byte limits precede retained
allocation and candidate-map publication. Zero items explicitly disables capture and queries.

Each immutable implication retains unique `(service, physical key, raw key)` facts in first-touch
order, including successful absent deletion and empty raw keys. Rewrites/deletions share the
original immutable fact. Hash collisions with different raw bytes refuse rather than overwrite
identity provenance. These are identities, not an ordered operation log or a last-value record:
resolve final presence/value only on that exact selected implication's account snapshot.

All immutable successors preserve the trace; checkpoint replaces the exceptional owner with the
current regular owner. Actual outcome selection therefore retains matching regular, panic and
out-of-gas facts without guest replay. Failed operations publish neither maps nor facts. Copied raw
keys are detached; default, disabled, out-of-range and copy-budget refusals remain typed.

Dispatch and the current guest policy carry the explicit optional capture policy. Default consumers
retain their previous behavior. Follow-up producer/state composition must bind selected invocation
histories to the exact original parent and full successor, retain untouched identities, and handle
creation/ejection, requests/preimages and non-guest writes before claiming complete propagation.
The held general supplied-delta reconciliation API is still absent.

Completion checks: `make unit SUITE=accumulation_storage_identities` for real dispatcher and direct
immutable host operations, detached ownership, checkpoint selection, quota/backend recovery and
1,000 ARC retirement cycles; existing write/effect/outcome and guest consumers plus strict guards,
privacy rejection, inventory and both formatting gates. M1 framing is complete; independent full
current-schema STF and crypto/privilege gates remain separate.

The unique facts also retain [latest-touch lifecycle phases](service-post-birth-evidence.md), without changing identity counts or first-touch order. Phase refreshes preserve retained original/checkpoint owners; phase metadata is not a total operation log or cross-invocation ordering authority.
