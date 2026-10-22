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


## WebSocket method contract

`ragnarok_requestStateProof(header_hash, keys)` accepts a canonical padded Base64
32-byte block hash and an array of 1–16 unique canonical padded Base64 31-byte
serialized state keys. It returns a connection-local integer request ID after bounded
selector capture. The acknowledgement means queued intent, not successful selection
or proof generation. One outstanding request per connection returns error 0 on further
admission. Invalid selectors/params return -32602 without consuming an ID. Notification-
form requests are ignored because no caller can receive the acknowledgement.

`ragnarok_cancelStateProof(request)` returns true only when it discards that connection's
queued or dispatched intent. It may be called in notification form. Completion already
queued is terminal and cancellation returns false; it does not remove that notification.
Cancellation never preempts native execution or releases its canonical lease.

Exactly one terminal `ragnarok_stateProof` notification carries `params.request` and either
`params.result` or `params.error`. Success is an object with `header_hash`, `state_root`,
`format: "RPV1"`, and `proof` (canonical padded Base64 RPV1 planned proof bytes). Error is
a fixed diagnostic string; no partial proof bytes are returned. Consumers independently
select the exact expected block/root and keys and use `decodePlannedProofs` with their
own receive ceilings. The returned root is metadata, never an independent trust anchor.
RPV1 remains the existing local state envelope inside this explicit Ragnarok extension;
this does not assign a JAM networking message or a standard JIP-2 proof method.

The raw proof ceiling is 32,768 bytes. Terminal messages share the existing 16-update,
65,535-byte per-connection FIFO with chain subscriptions. Overflow retires only the
consumer; no partial queue mutation commits. Batches retain sequential execution and
reply-budget transactionality. Methods are advertised only on stateful connections whose
canonical host explicitly enables proof production; stateless/default listeners return
-32601. Listener/Services binding is supplied by the following layers.
