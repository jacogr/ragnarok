# Publish composed computed state

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation and authenticated state transitions; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Consume only ComposedComputedState and the target full StateStore. Delegate to
publishAccumulationState with its actual retained PreparedAccumulationConsensus.
Require exact original parent identity, never root equality; complete all refusing
work before replacing the sole mutable target handle. Retain original computed
provenance and exact published snapshot in a closed publication receipt. Preserve
the complete selected underlying refusal; no guest replay or state recomposition.
This publishes the implemented state transition; it does not advance a chain view
or establish complete chainspec, serialization or whole-block parity.

Completion: genuine compute/sign/admit/execute/finalize/compose/publish; exact
prepared map identity, pending C10 and C16, aliases and historical views, replay,
equal-root different-owner, authenticated prefix and changed target refusals;
uninitialized/default sources and complete nested reasons; no hashing during
publication; detached/copy/1000-cycle ARC and strict runtime/compiler guards.

Next: capture a direct-child chain view from the genuinely composed computed
state under coherent original profile domains, before atomic state/view advance.
M1 framing complete; full state serialization open.

Observed local evidence: genuine publication retains the exact prepared complete
map and original computed provenance; current pending C(10) and fresh C(16)
survive adoption. Replay, a changed target, the already prepared candidate and a
byte-identical re-applied parent all refuse as StaleState without mutation. An
uninitialized target retains StateFailure/Uninitialized; an invalid source leaves
the original target usable. Publication and refusal checks make zero Blake2b
calls with hashing forced to fail. Detached receipts and independent snapshot
handles remain valid. Native ARC stays 684096/684096 bytes over 1000 cycles.
Nine optimized runtime guards, five compiler guards, 35 verification-tooling
tests, inventory and pinned formatting pass. All 3333 previously covered
composition source/dependency/config inputs remain identical, so that native
evidence is reused. These are local macOS checked-release results; no remote CI
was requested.
