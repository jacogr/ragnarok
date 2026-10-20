# Bounded finalized successor handoff

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Schedule only existing opaque
PreparedFinalAccumulation owners through the application coordinator. PVM owns
execution and finalized successor selection; no detached map/header or new wire
input can confer authority. This is a dispatcher handoff, not a live network importer.

## Contract and completion tests

One private handoff slot is Idle, Pending or Finished. Enqueue is hash-free and
requires an initialized canonical owner, a valid finalized source and exact retained
parent identity. Pending and unacknowledged Finished slots refuse replacement.
Enqueue copies explicit composition limits and retains the immutable source.

Each Services.tick attempts at most one Pending candidate before RPC/UI request
work, using the existing coordinator and startup RPC choice. All success/failure
outcomes remain Finished until the producer takes the guarded result. Idle and
Finished ticks perform no adoption work, including no automatic retry. Taking a
result clears the slot; only Pending can be explicitly cancelled. Close retires
pending sources and unacknowledged results. Direct adoption remains supported, and
any intervening canonical change makes the queued old parent refuse at commit.
Enabled RPC closure refuses without silently falling back. No mutex, thread,
reentrant callback, unbounded queue or inferred resource budget is introduced.

Both peer shapes invoke the same service tick. Test genuine source execution from
the configured seed, deferred publication, exact one-attempt hash counts, immutable
old readers, Busy before/after processing, default/stale sources, cancellation,
late failure and explicit retry, direct interleaving, closed RPC, result acknowledgement,
shutdown/restart and allocation-stable retained-owner cycles. Use actual loopback
RPC subscription/query observations. Add private storage and selected-completion
compiler/runtime guards, retain Services non-copyability, and run affected service
and executable state-policy lifecycles, inventory/tooling and pinned formatting.

## Observed verification

Checked optimized native `application_handoff` passes with genuine re-admission,
PVM finalization and real loopback RPC publication. It proves hash-free enqueue,
one-attempt hash parity with direct adoption, Busy pending/finished slots, explicit
acknowledgement/cancellation, stale direct interleaving, captured composition limits,
late capture failure/retry, closed/stale RPC refusal and scoped-source retention.
Shutdown releases both pending and unacknowledged finished owners. All 1,000 cycles
cover pending cancellation/destruction, taken/untaken success and taken failure,
retaining 118,800 occupied bytes before/after. Affected `application_services` also
passes with 1,000 cycles retaining 114,208 bytes before/after.

Four handoff/service privacy probes, the existing Services copy-lowering rejection,
and both strict idle-completion runtime guards pass. The normal executable builds;
its registered state-policy workload passes standalone and retained mesh lifecycles,
RPC queries and invalid startup refusal with the shared service tick. Legacy RPC/UI,
configured genesis/service queries and shared telemetry startup checks pass too.
These executable checks exercise idle handoff dispatch; genuine queued publication
is exercised by the native suite through public Services and real RPC sockets.

Inventory passes with 204 native suites, 139 failure families and 1,872 data-driven
probes. All 40 affected verification/failure/mesh/RPC Python harness tests pass.
Pinned Nim/Rust formatting and whitespace checks pass. These are local macOS
results; complete/Linux verification remains in CI.

## Remaining work

Validated candidate acquisition and execution scheduling still need a real producer;
no development transport message is interpreted as a block. Consensus/fork choice,
durable restart and full/light database modes remain open. M1 framing is complete;
full state serialization and JAM/STF parity remain open.
