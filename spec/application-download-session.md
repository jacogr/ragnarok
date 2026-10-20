# Joined download session lifetime

## Scope and authority

Join the [download scheduler](application-download-schedule.md),
[CE 128 stream controller](application-download-stream.md) and existing block
receiver in one non-copyable `quic/block_download_session` owner. Preserve JAMNP-S
`439c45aad135dc654b3de6f56d7d694fd02b7aa8` and the GP/vector pins in
[block download](application-block-download.md). No wire or consensus rule changes.

## Contract and completion tests

The caller retains this owner at a stable address until every native close.
It supplies authenticated peer identities, stage/resource policies and monotonic
ticks. The session privately owns its schedule, receiver and callback binding;
callers receive only immutable attempt tokens, fixed request copies and guarded
results. Exact token identity rejects stale/cross-session events even when local
peer IDs match. Native events additionally check the selected peer and live handle.
The host must abort a late-opened native stream when binding is refused.

Begin reserves one scheduler lease and admits the selected application context.
Admission failure releases that lease as a failed attempt without a native binding.
Invalid native policies and handles preserve the admitted request for retry or
explicit discard. Callbacks only route bounded I/O; cancellation retains the native
binding. Finish, discard and enqueue refuse while that binding awaits actual close.
No callback executes a guest or publishes state. Empty/failed receiver outcomes
remain inspectable until terminal acknowledgement; close preserves their reasons.

After close, explicit enqueue delegates to the existing Services producer and
retains the lease through handoff backpressure. Only complete enqueue success
marks it queued. The host drives the later service tick, takes the actual adoption
outcome and explicitly reports Adopted or Retry. This acknowledgement is trusted
host lifecycle input; the session does not certify a supplied adoption outcome.
Adopted is refused before enqueue. Retrying a Ready/Receiving input requires an
explicit discard after close. Clock refusal preserves the complete attempt so
acknowledgement can be retried. All default/refused results expose reasons alone.

Test signed real block transfer, failure/empty/cancel/deadline retirement, native
close barriers, wrong peers/handles/tokens, stale and cross-session attempts,
invalid policy/binding retry, typed admission/preparation failure, queued
backpressure and genuine deferred adoption. Observe no callback hashing, ARC
release and actual composite-copy/privacy/nominal/result guards.

## Verification

Local macOS verification with pinned Nimony/ARC, checked optimized Clang/LTO:

- `make unit SUITE=application_download_session` passes the signed two-guest block,
  real authenticated LSQUIC failure/empty/healthy transfers, explicit cancellation,
  injected reset-event routing and deterministic expiry. It observes native-close
  barriers, selected framing/decode reasons, foreign/forged/stale tokens, binding
  retry, handoff backpressure and later canonical adoption. Native reception and
  malformed-block decode perform zero observed Blake2b calls.
- The session's 1,000 lifecycle cycles retain 8,803,936 occupied bytes before and
  after. `make unit SUITE=application_block_download` also passes after the shared
  responder/provider extension, retaining 8,806,720 bytes across its 1,000 cycles.
- Three privacy probes, the exact nominal token/lease rejection and actual
  composite-copy lowering rejection pass. All five strict runtime result guards
  and the genuine successful admission/extraction control pass.
- All 56 affected native harness tests and 35 verification tooling tests pass.
  Inventory passes with 229 native suites, 160 failure families and 2,024 declared
  probes. Pinned Nim/Rust formatting and whitespace checks pass.

Evidence is under `build/download-session-*` and
`build/tests/native/selected/`. These are local checks; exact-head Linux/full CI
remains separate evidence and is not requested by opening this PR.

## Remaining work

The joined owner is a production component used by the native integration fixture.
The [authenticated peer catalog](application-download-peers.md) now owns pinned
outgoing transports and maps selected tokens to their actual native streams.
Command-loop wiring and execution workers remain open. Authentication,
execution and canonical adoption retain their existing owners. Persistence,
consensus and full/light databases remain open. M1 framing is complete; full state
serialization and JAM/STF parity remain open.
