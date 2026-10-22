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
completion and uint32 exhaustion. Selector ownership alone does not confer method availability.

The following sections specify request/notification framing, reply-budget transactions, listener
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
Cancellation never preempts native execution or releases its canonical lease. Network cancellation
is processed when RPC resumes; if a terminal result is already queued, it returns false. An ordered
request/cancel batch can discard queued intent before host dispatch.

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
reply-budget transactionality. Proof terminal messages contribute to shared pending counts,
but do not occupy chain-subscription selectors. Methods are advertised only on stateful connections whose
canonical host explicitly enables proof production; stateless/default listeners return
-32601. The canonical Services binding is described below.


## Listener dispatch boundary

The host explicitly enables proof capability only after binding a live canonical Services
owner. After an RPC tick returns, the listener fairly claims at most one detached selector
from its eight connections. The routing ticket retains the original request's namespace,
not an fd or canonical snapshot. Connection slot/fd reuse cannot deliver an old result to
a new session. Scheduling and completion refuse while the canonical lease is paused;
the host must collect or join the worker and resume before delivery. Closing/restarting
the listener clears capability until an explicit host binding is installed again.

Native listener tests exercise two consumers, fair claim-once scheduling, cancellation,
replacement sessions, pause/resume delivery and count-limit disconnection isolation.
The Services integration suite checks real socket framing and native worker/receive verification.


## Canonical Services production

Canonical `server`, `client` and `mesh` startup enables proof production. Legacy/genesis-only
RPC has no canonical worker source and does not advertise the methods. The `download` command
also leaves production disabled: its ancestry orchestration retains external parent aliases
and requires separate scheduler integration before allowing an autonomous proof lease.

After each RPC/UI tick returns, Services fairly claims one connection request, then admits it
through `beginStateProof` outside callbacks. No temporary canonical alias survives into native
submission. One existing reusable worker slot provides the bound; this adds no per-connection
thread. Every request resolves one explicit retained block, including a separated finalized
anchor when available. Unknown/evicted selection, native failure, busy canonical ownership and
resource refusal yield a terminal error notification. Failure cannot return an empty proof or
claim key absence. Request acknowledgements are sent before terminal notifications.

Policies: 65,536 complete-map entries, 131,071 trie nodes, 1 MiB per map value and 8 MiB total
map values; 249 nodes per proof and 3,984 aggregate proof nodes; 16 selectors; 32 KiB individual,
aggregate, retained-view and encoded proof bytes; 4,000,000 conservative hash calls. These local
ceilings are independent of protocol validity and never widen on refusal. The existing request,
reply and notification ceilings apply in addition. The hash estimate is not a wall-clock deadline.

RPC chain processing stays paused through native Queued/Running/Done and resumes only after
exact collection or joined stop. Cancellation/disconnect does not preempt cryptographic work.
The existing socket wall-clock deadlines remain in force, so an expired/closed consumer can lose
delivery while its bounded work still retires safely. Joined close runs before canonical owners,
request selectors, RPC leases or sockets are released. Direct host proof calls preserve their
existing explicit-collection behavior; automatic collection is limited to RPC-owned tickets.


## Verification and remaining scope

`rpc_proof_requests`, `rpc_proof_protocol` and `rpc_proof_transport` cover selector ownership,
strict framing, acknowledgement transactionality, cancellation, namespace reuse, fair scheduling,
and FIFO overflow isolation. `rpc_state_proofs` uses real medium WebSocket frames and native
Services jobs. It independently supplies the selected root/plan to `decodePlannedProofs`, reads
a typed global time/account and proven absence, and rejects wrong roots, modified bytes and
wrong selector scope. Unknown block selection and native hash refusal return terminal errors.
The suite also checks queued cancellation, busy batches, joined stop/close, download exclusion
and 1,000 repeated-job ARC retirement cycles. Existing RPC and Services consumers retain coverage.

These APIs provide evidence for already selected complete state, not a new source of root
trust, consensus finality, a light-state database, submission routing or DA retrieval. Download
scheduler integration remains explicitly separate. M1 framing is complete; full JAM serialization
and whole-block STF parity remain open.
