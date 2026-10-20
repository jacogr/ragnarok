# Application block input

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Reuse the existing C.2 block codec
and application candidate producer. This boundary receives a single raw block
payload with a caller-supplied exact extent, not a JAMNP stream envelope. Do not
invent a block-stream selector, request format or consensus selection rule.

## Contract and completion tests

One non-copyable input owner retains at most one bounded payload and bounded
immutable ancestor handles. Admission captures the exact selected application
history and explicit candidate policies. Reject missing state, profile mismatch,
zero/oversized/non-host-sized extents and ancestor count/byte limits before payload
allocation. Validate ancestor owners before retaining them. No inferred defaults.

Each admitted input receives a nonzero monotonically increasing local generation.
Fragments/cancellation require that generation; stale callbacks cannot affect a
replacement. Copy fragment bytes into one preallocated buffer, checking remaining
capacity before arithmetic or writes. Final input must exactly match the admitted
extent. Short/overlong input retires the slot; an exact nonfinal prefix remains
Receiving. Ready rejects further fragments without replacing its bytes.

Receiving/cancellation perform no decoding, hashing, execution or publication.
An explicit producer call outside transport callbacks consumes Ready once,
checks the selected history still matches, decodes exactly one complete block,
rejects trailing bytes and delegates to prepareCandidate. Terminal success and
refusal both retire raw input. Results expose only finalized success or the actual
selected codec/preparation reason, never a successful prefix. Stale/not-ready
calls leave the slot unchanged. Services may enqueue finalized success only when
its existing handoff is idle; Busy precedes preparation and retains Ready input.
Canonical state/RPC still change only on the later service tick.
The producer owns this receiver independently of Services and retires its callbacks
before replacing/destroying it. Service shutdown does not transfer that ownership;
preparing against closed/restarted canonical state refuses the changed history.

Test every split of a signed real block, caller-buffer mutation, stale generation,
cancellation/reuse, exact final input, zero/oversized extents, host narrowing,
ancestor count/bytes/owner refusal, wrong profile and missing state, Ready
backpressure, selected-head changes, complete-prefix trailing bytes, malformed
codec and real execution refusal, retry, deferred service adoption and repeated
success/cancellation ownership. Retain privacy, nominal, copy and selected-result
guards. Run affected producer/service suites, inventory, tooling and formatting.

## Observed verification

Checked optimized native `application_block_input` passes every two-fragment split
of the genuine signed two-guest block, caller-byte mutation, exact completion,
size/domain/ancestor refusals, stale generations, copied-ancestor typed rejection,
exact codec consumption, selected-history changes, actual execution failure and
deferred service adoption/backpressure. Its 1,000 alternating successful preparation
and partial-reception cancellation cycles retain 152,272 occupied bytes before/after.

The shared signed-seed fixture retains all existing producer assertions:
`application_candidate` passes, including real loopback RPC publication and 44 gas
consumed by the two halt guests, with 151,968 occupied bytes unchanged over 1,000
cycles. `application_handoff` passes with 118,800 bytes unchanged over 1,000 cycles.
Three privacy probes, one nominal generation probe, the receiver copy rejection
and all seven strict selected-result runtime guards pass.

The normal executable builds and its parser/frame and UDP I/O selftests pass.
Inventory passes with 206 native suites, 141 failure families and 1,890 declared
probes; 43 affected verification/failure-harness Python tests pass. Pinned Nim/Rust
formatting and whitespace checks pass. These are local macOS results; exact-head
Linux/full verification remains in CI. No live block network stream is claimed.

## Remaining work

JAMNP block-stream acquisition and dispatcher wiring, worker scheduling and a live
producer loop remain open. Preparation is synchronous and explicitly outside
transport callbacks; service ticks do not execute queued raw blocks. Consensus,
durable restart and full/light database modes remain open. M1 framing is complete;
full state serialization and JAM/STF parity remain open.
