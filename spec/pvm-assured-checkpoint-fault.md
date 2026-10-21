# Guard-page faults select checkpointed storage deletion

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, scalar
loads, exceptional accumulation selection and checkpoint assignment in
`text/pvm.tex` and `text/pvm_invocations.tex`; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: author ReadCheckpointFault before original refinement, signing and
execution. Fetch the real input count, delete key11, checkpoint absence, read
NONE and restore eleven regular bytes. Count1 halts; count2 executes a literal
load_u8 at guard address131072. The unmapped page must terminate the actual
invocation and select the checkpoint deletion. No terminal or memory is patched.
The original parent retains its key, account, balance58 and code. Only the new
mode receives the existing checkpoint policy (32 steps, five calls, capture11).
Older guest bytes and all protocol parameters remain unchanged.

Completion: original Halt/Regular and assured Panic/Exceptional with MissingKey,
one selected deletion proof/zero selected value bytes, exact28/27 step ceilings,
copy11/10 and calls3/4 refusals, selected-key/provenance boundaries, complete
composition and publication, timestamp3/history3/activity2/actual gas/all29
parameters/aliases/finality1, and1000 ARC release cycles. Run affected predecessor
and inventory/format/tooling checks. This layer extends the prior trap witness to
an actual guest memory fault. It does not change scalar wrapping semantics.

Next: verify checkpoint selection after protection faults and host-memory panics.
M1 framing complete; complete state serialization, whole-block parity and full
chainspec equivalence remain open.

Observed: the genuine original count1 guest halts in Regular and creates the
eleven-byte key; the genuine assured count2 load at131072 completes as normalized
Panic/Exceptional and publishes MissingKey. Exact28 steps/copy11 succeed; steps27,
calls3/4 and copy10 refuse at their expected local boundaries. Zero selected value
capture succeeds; zero final keys and zero provenance keys refuse precisely.
Canonical composition/publication, preserved aliases, metadata, gas and parameter
checks pass. One thousand full successors retain753888/753888 occupied bytes.

Validation uses the existing checked-release macOS/ARC/Clang LTO native runner.
The predecessor checkpoint and assured-outcomes suites also pass1000 cycles,
retaining753888 and3162032 bytes respectively. The native harness passes37 tests
and inventory recognizes the new suite. Remote Linux CI remains separate.
