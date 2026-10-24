# Full checkpoint reconstruction during current STF continuation

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and the
existing independent upgrade/request/provision/creation/supervisor feature equations.
The checkpoint envelope is local full-map storage, not JAM state wire serialization.

Five selected independent transcripts cover an upgrade followed by current-code
execution, checkpointed request removal, checkpointed provision, two public child
creations and protected-pool authority loss. After every installed child the driver
encodes the entire map, decodes it into a new full store, captures the exact selected
header with the same Parameters and original writable store policy, verifies public
policy identity, finalizes that restored base and initializes a new
application chain. Actual older header owners remain separately retained for report
anchor checks. No private certificate, partial map or light-state root is invented.

Thirty reconstructed successors must retain byte-for-byte identical signed blocks,
full checkpoints and roots from the independent lifecycle equations. This checks
that in-memory prepared owners do not hide state needed by subsequent admission,
code lookup, request history or service membership. Frozen source fixture hashes
bind each selected transcript to its original independent evidence.

Checked ARC/Clang replay and ordinary manager/creation regressions pass locally,
with independent full-map canonicality and signed parent/root continuity invariants,
pinned formatting and inventory. Linux CI is separate. Existing production logic,
pins and historical fixture bytes remain unchanged. M1 framing is complete; this
proves local full-checkpoint continuation, not complete JAM serialization/parity.
Epoch/lifecycle composition remains the next bounded integration step.

Read-only genesisStoreLimits has a zero-write budget and cannot authorize later
execution. Restoration uses the known fixture policy, including inherited
write/item/byte ceilings, and asserts sameStateStorePolicy before any next candidate.
