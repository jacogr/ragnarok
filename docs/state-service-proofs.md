# Proof-backed service reads

Use `state/proof/service` when a reader has authenticated partial evidence rather
than a complete execution map. Current supervisor-aware account metadata and the
bounded request namespace follow unreleased Gray Paper commit
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`; VERSION remains 0.8.0.

## Choose and retain authority

Select the block/root independently of the response. A root in a caller-selected
`BlockSnapshot` is its posterior complete-state root; its header contains a prior
state root. Neither a query plan nor the local envelope discovers chain trust,
confirms finality or authenticates consensus on its own.

`ServiceProofPlan` contains immutable sorted requested identities. Account,
storage, preimage, request and historical constructors include the canonical
account dependency. `mergeProofPlans` coalesces shared identities under an exact
unique-key limit. Code planning can learn the current code hash from a verified
account; that root-free plan still grants no authority. Historical length hints
request evidence; the reader independently selects actual authenticated length.

## Generate and receive

The producer calls `generateServiceProofs` on a complete immutable snapshot or
`generateBlockServiceProofs` on an explicit selected block. It cannot substitute a
partial map for complete state. Snapshot batch generation preflights and copies
the complete map once, then produces bounded individual paths. This is neither
multiproof compression nor a production sizing/performance claim.

The receiver calls `verifyServiceProofs` with the retained plan, exact raw query
records and its independently selected root. Requested identities must match
exactly, then every witness authenticates atomically. The stricter aggregate/view
count and value ceilings apply. No verified prefix escapes a later failure.

For local transport, `encodeServiceProofs` and `decodeServiceProofs` reuse RPV1
and RSP1. They add exact plan matching, not a new network protocol or a trusted
root field. Receivers apply their own wire, per-proof, aggregate and view limits.
These APIs do not add a public proof RPC, light database or startup mode.

## Read typed facts

| Read | Evidence and meaning |
| --- | --- |
| `readProofAccount` | Exact 105-byte canonical current metadata; no completeness claim for nested maps |
| `readProofStorage` | Same-root account and bounded raw storage value, including present-empty bytes |
| `readProofPreimage` | Same-root account and bounded content, with advertised Blake2b hash checked |
| `readProofRequest` | Same-root account and exact canonical history; reserved lengths fail before hashing |
| `proofPreimageRequested` | True only for Requested; proven absent account/request is false |
| `readProofHistoricalPreimage` | Account, checked content and actual-length history at an explicit slot |
| `readProofCode` | Historical content selected from this view's authenticated current account code hash |

A missing witness never means authenticated absence. `MissingWitness` asks for
more evidence; `AbsentValue` reports proven account/value absence or historical
unavailability. A missing required history beside a present preimage is malformed
state. Invalid committed bytes remain `InvalidValue`. Hash refusal remains
`BackendFailure`, while response authentication preserves a guarded nested
`StateProofError` under `ProofFailure`. Never extract a failed/default result.

Historical slots are explicit query inputs, not independently authenticated chain
anchors. The pinned four-shape interval equation adds no chronological ordering
rule. Code resolution returns bytes; program validation and PVM execution retain
their existing boundaries. Successful account reads do not validate balances,
storage footprints, every nested record or complete JAM state invariants.

## Ownership and verification

Plans, witnesses and views retain private immutable acyclic ARC owners. Detached
value copies cannot mutate them. Original responses remain bound to their old
roots after complete-map successors publish or source stores are released.
Partial proof views and requested-key plans cannot become complete StateStore
snapshots or authorize a state transition.

The [feature contract](../spec/state-proof-service.md) records native suites,
frozen independent namespace/current-metadata/full-root witnesses, real primitive
failure prefixes, signed successive-head transport, strict extraction/privacy
checks and 1,000-cycle ARC success/rollback evidence. Local checked native results
are separate from exact-head Linux CI. M1 framing and the adopted request-domain
correction are implemented; complete JAM serialization and STF parity remain open.

See [partial proof views](state-proof-views.md) and [trie proofs](state-proofs.md)
for underlying envelope, root and path-validation boundaries.
