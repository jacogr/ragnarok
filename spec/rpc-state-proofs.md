# Bounded asynchronous RPC state proofs

Scope: bind the merged selected-state query API to a Ragnarok WebSocket extension;
no JIP-2 method or JAM wire assignment is changed. State interpretation follows the
recorded unreleased GP pin in `spec/pins.json`, including the adopted request namespace.
RPC selects an exact retained block's posterior complete-state root. Response bytes
carry evidence only: consumers independently select the expected root and exact plan.

## Request ownership foundation

Each connection owns at most one queued or dispatched selector containing 1–16 exact
31-byte state keys and a 32-byte block hash. Capture copies and sorts selectors and
rejects duplicates. A connection-local nonzero uint32 request ID never wraps. Private
namespace ownership also binds completion to the original session, so reused public IDs
on replacement connections cannot accept stale work. Cancellation discards logical intent;
native worker capacity and canonical exclusion remain owned until collection/join.

Completion checks: `make unit SUITE=rpc_proof_requests` covers detached keys, duplicate/count
limits, busy/unknown/default cases, claim-once, cancellation, exact/foreign/stale/reset
completion and uint32 exhaustion. This foundation does not yet advertise RPC methods.

Next layers: bounded request/notification framing and reply-budget transactions, listener
routing, managed Services admission/collection, independent receive verification and shutdown.
M1 framing completion does not imply complete state serialization or whole-block STF parity.
