# Computed guest storage reaches canonical chain state

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
pvm_invocations.tex write (5), accounts.tex footprint/threshold equations and
authenticated accumulation transitions; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Exercise the actual computed/refinement, credential, admission, accumulation,
finalization, composition and atomic state/chain path with an authored storage
write. Entry zero jumps over the accumulation body to empty refinement output;
entry five loads real memory pointers and invokes write (5). Code, package gas,
deposit parameters and original account balance are authored before roots,
signing and computation. Nothing patches completed source certificates.

Completion: halt persists key[11]/value[21,22,23], one storage item and 38 bytes;
10+2*1+1*38=50 accepts exact balance50 while49 refuses; panic after write selects
exceptional state and discards that write. Distinguish actual termination and gas,
original-parent immutability, normalization, finalization, prepared state and
canonical chain state/head; pending reports and activity remain coherent.
Retained/detached views and1000-cycle ownership checks plus affected consumers
use real maintained execution, never expected-effect injection.

Next: retain a write through a guest checkpoint before a later panic, and verify
the selected exceptional state through the same complete publication path.
M1 framing complete; full serialization, full chainspec equivalence and whole-
block parity remain open.

Observed local evidence: all three genuinely authored programs pass through
credential verification, admission, actual service execution and stopped
finalization into canonical chain publication. Commit persists the exact row,
38-byte footprint and one item at balance50. Panic selects Exceptional and
removes that write; balance49 selects Halt/Regular while retaining absent storage.
Selected outcome, finalized map, composed map, published store and best-head map
agree. Original parent/aliases remain unchanged; lastAccumulation becomes2 and
C(13) records two refinements, one accumulation and exact actual guest gas.

Only this fixture enables one provenance key, one published self key and three
value bytes. Actual executions with disabled tracing refuse through
RunnerFailure/CompletionFailure/BatchFailure/UnsupportedAccountEffects; a zero
publication-key budget or two-byte value ceiling refuses with LimitExceeded.
These are local policy refusals, not guest panic or FULL. Production defaults
remain unchanged. Unexpected fixture refusals now print their precise originating
runner/dispatch/completion/batch stage before stopping.

Native storage ownership remains1446000/1446000 bytes over1000 cycles, each
publishing all three outcomes. Fresh chain/transition consumer suites also pass
1000-cycle checks (1079904/1079904 and292720/292720 bytes). Twenty-eight existing
optimized chain guards,35 verification-tooling tests, inventory and pinned
formatting pass. All1703 covered production/native/compiler-fixture/toolchain
inputs remain unchanged, so prior compiler-guard evidence is reused. These are
local macOS checked-release results; no remote CI was requested.
