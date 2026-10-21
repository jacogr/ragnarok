# State and execution composition

[Source guide](../README.md) · [State design](../../docs/design/state.md)

This folder owns complete serialized state snapshots, bounded transition plans and the
provenance-preserving composition of protocol execution stages. The feature families are broader
than a single block executor; their exact supported boundaries live in the linked contracts.

| Area | Contents |
| --- | --- |
| [`store.nim`](store.nim) | Atomic write batches, immutable complete-map snapshots, retained values and private forks |
| `checkpoint*` | Complete-map checkpoint encoding/validation, bounded file access and managed publication workers |
| Authorization, entropy, history, validators, tickets and Safrole | Bounded component transitions and atomic chapter publication |
| `block_*`, `extrinsic_inputs`, report and guarantee modules | Structural admission, authentication/projection boundaries and selected block transitions |
| [`ancestor_context.nim`](ancestor_context.nim) | Immutable sealed ancestry, child-committed lookup proofs and [bounded report context discovery](../../spec/state-ancestor-context.md) |
| `accumulation_*` | Prepared service inputs, credited execution contexts, host effects, continuation/reentry and selected successor composition |
| Refinement, assured/computed, bundle, import/export and erasure modules | Bounded work execution, provenance, data availability and publication stages |

`StateStore` retains a complete full-state mapping and uses the incremental
[storage trie](../storage/README.md) for commitment updates. Lookup/iteration and retained values
preserve immutable ownership; failed private updates publish neither partial bytes nor a new
head. Complete-map checkpoints remain distinct from canonical durable-head recovery.

Full/light node startup and database selection remain separate work. Partial light state cannot
be presented as a complete state root. The standalone disk repositories in `storage/` have their
own integration boundary; sharing commitment primitives does not adopt those repositories here.

Start with the [store contract](../../spec/state-store.md),
[incremental integration](../../spec/state-store-incremental.md),
[checkpoint contract](../../spec/state-checkpoint.md),
[block admission](../../spec/block-admission.md) and
[PVM/state successor boundary](../../spec/pvm-state-successor.md).
The [state design](../../docs/design/state.md) links the transition families and their verification;
component coverage does not imply complete JAM state serialization or a production validator.
