# Application state in service lifecycles

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Extend the existing non-copyable Services
owner with an opt-in configured application chain. Preserve the proof-peer startup
overload; no CLI policy, protocol equations or PVM execution changes belong here.

## Contract and completion tests

`Services.start(options, role, StateStoreLimits)` requires an explicit complete-state
policy and complete configured seed even when RPC is disabled. Read the bounded
chain file once; initialize the canonical map once and seed enabled RPC from its
exact retained head and parameter tuple without decoding the map or rehashing again.
Telemetry continues to use the same captured text. No missing/invalid seed fallback.

Only immutable state/history accessors escape. Adoption delegates the existing
application coordinator; the RPC choice is retained at startup, so a subsequently
closed enabled listener refuses instead of silently using independent adoption.
A second start refuses without disturbing the live owner. Close/destruction retire
listeners and canonical owners after dispatcher/native borrows end; close is
idempotent and restart requires a new configured seed. Explicit close also releases
RPC's retained history. Old reader snapshots remain valid independently.

Test real temporary chainspec files, no-RPC and loopback RPC startup/adoption,
one-pass hash counts, exact identity, genuine re-admission/finalization, immutable
old readers, missing/malformed/short-policy seeds, occupied listener and UI failures,
repeat start, listener closure, close/restart and repeated ARC-stable owner cycles.
Retain Services non-copyability and private canonical state/routing compiler guards.
Run affected application/RPC/options consumers, inventory, tooling and formatting.

## Observed verification

Checked optimized native `application_services` passes, including real files,
loopback subscriptions, genuine execution/finalization against the decoded seed,
atomic adoption and closed-listener refusal. Startup uses the same hash count as
standalone configured initialization. Early and final-header hash failures retire
the seed; RPC bind failure releases an already opened UI port. All 1,000 alternating
explicit-close/implicit-destruction cycles retain 114,208 occupied bytes before and
after. Both canonical/routing privacy probes and the existing Services copy-lowering
rejection pass. The executable builds and its existing live RPC/UI, configured
parameter/genesis/service queries and shared telemetry startup checks pass.
Native `app_options` also passes. Inventory passes with 203 native suites, 137 failure families and 1,866 data-driven
probes; all 26 verification-tooling Python tests pass. Pinned Nim/Rust formatting
and whitespace checks pass. These are local macOS results; full/Linux verification
remains in CI.

## Remaining work

The executable must select an explicit application state policy and opt into this
startup path; development peer commands keep their existing behavior. Live import
scheduling, consensus/fork choice and persistent restart remain open. PVM owns
execution and finalized successor selection. M1 framing is complete; full state
serialization and JAM/STF parity remain open.
