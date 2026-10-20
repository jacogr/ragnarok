# CE 128 native stream routing

## Scope and authority

Add one reusable `quic/block_download_stream` controller above the existing application
download owner. Preserve JAMNP-S revision `439c45aad135dc654b3de6f56d7d694fd02b7aa8`,
Streams, Messages, Notation and CE 128; this layer changes no wire representation.
GP 0.8.0 and vector pins remain unchanged. The development proof-peer commands keep
their existing workload until explicit peer selection and execution scheduling exist.

## Contract and completion tests

Bind exactly one live native handle to one receiving download generation and stable
receiver address. Every callback and cancellation checks all three identities before
native I/O or receiver mutation. The address is compared only, never dereferenced.
Callers keep the receiver and callback mapping stable until the final native close.
Native transport owns the handle; the controller cannot be copied or rebound before
close, including while cancellation is pending. Retire transport callbacks before
destroying either application owner. Destruction checks that close retired the binding;
it never calls through a borrowed handle. Both copy and duplication hooks prohibit
duplicating this scalar-only callback owner.

Explicit byte limits bound each callback to one read or write. Fixed request storage
retains partial-write offsets; would-block and zero-byte writes yield without spinning.
Queue request FIN exactly once after all bytes; only an actual zero-byte read supplies
response FIN. Preserve typed application framing failures through teardown. Reset,
premature close and deadline cancel incomplete input; neither fabricates a successful
prefix. Both completed halves survive ordinary close. Explicit cancellation can retire
Ready input, but keeps the native binding until close. Deadlines use caller-supplied
monotonic millisecond ticks with checked subtraction, never network wall-clock values.

Exercise the production controller over real authenticated LSQUIC streams with tiny
read/write budgets: healthy, empty, malformed, premature close, absent FIN, explicit
cancel, deterministic expiry and reset-event dispatch. Check wrong handles, generations,
receiver addresses, duplicate binding, zero/oversized policies, late events and reuse.
Observe zero hashing in callbacks and genuine deferred preparation/adoption afterward.
Retain privacy, nominal and composite-copy compiler rejection checks and ARC evidence.

## Observed verification

`make unit SUITE=application_block_download` passes with the production stream
controller replacing the test client's native read/write loop. Real authenticated
LSQUIC exchanges cover healthy signed-block transfer, byte-at-a-time empty framing,
oversized response, premature close and complete bytes without FIN. Separate live
streams exercise deterministic deadline expiry and injected reset-event routing;
the latter is callback coverage, not evidence of a wire RESET_STREAM. All close
callbacks retire the controller before transport/callback owner destruction.

Binding checks reject absent receivers, stale IDs, missing handles and zero/oversized
callback policies without enabling I/O. Foreign receiver/handle/generation events,
unknown events, late read/write/close callbacks and duplicate resets are inert.
Cancellation retains the binding and rejects rebinding until close; stopping callbacks
leave copied-byte counters unchanged. Backward/pre-deadline ticks do not expire input,
and the exact deadline does. Selected framing failures survive transport teardown.

Reception and native callbacks perform zero observed Blake2b calls; genuine guest
preparation occurs after transport teardown and canonical adoption waits for the later
service tick. Existing 1,000 complete/partial framing release cycles retain 8,806,752
occupied bytes before and after. This ARC observation covers the application receiver;
native stream retirement is checked separately by the seven transport scenarios.

Two privacy probes, the nominal tick/duration probe and explicit composite-copy lowering
rejection pass. Five verification-guard harness tests, inventory and pinned Nim/Rust
formatting pass. These are checked optimized local macOS results; full/Linux CI remains
separate and is not requested by opening this PR.

## Remaining work

The [download scheduler](application-download-schedule.md) now supplies bounded peer
rotation, cooldowns and attempt leases. Production peer-catalog/command wiring and
bounded execution workers remain open. This controller does no decoding, hashing,
PVM work, canonical adoption or serving/finality selection. M1 framing is complete; full state
serialization and JAM/STF parity remain open.
