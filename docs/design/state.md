# State storage and transitions

[Design overview](../design.md) · [State source map](../../src/state/README.md) ·
[Storage direction](state-storage.md)

[The state store](../../src/state/store.nim) owns complete serialized maps.
[The trie](../../src/storage/full/state_trie.nim) supplies commitments and immutable
revisions. [Checkpoint encoding](../../src/state/checkpoint.nim) and
[file publication](../../src/state/checkpoint/file.nim) provide detached full-map
export and recovery input. The application separately establishes trusted head identity.

[Block admission](../../src/state/block/admission.nim) binds the exact parent and
block commitments. [Block transition](../../src/state/block/transition.nim) composes
disputes, Safrole and assurances before [report admission](../../src/state/report/admission.nim)
and [queue planning](../../src/state/accumulation/queue.nim). Each stage owns its
specific structural or execution certificate.

## Full and light node modes

Startup selects a mode-specific owner and database. [Full state](../../src/state/store.nim)
supplies complete execution inputs. The [light actor](../../src/app/light/runtime.nim)
combines trusted header evidence and partial proofs. Shared codecs retain the same
wire semantics across modes.

## Accumulation successor boundary

State consumes an exact execution successor for composition and publication.
[The shared boundary record](../../spec/pvm-state-successor.md) identifies the
execution authority and the [PVM design map](pvm.md#accumulation-successor-boundary)
shows the division between the two owners.
