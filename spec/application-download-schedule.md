# Bounded download peer scheduling

## Scope and authority

Continue the [CE 128 controller](application-download-stream.md) with one explicit
host scheduling policy. Preserve pinned JAMNP-S `439c45aad135dc654b3de6f56d7d694fd02b7aa8`
and the GP/vector pins in [block download](application-block-download.md). This
changes no wire format or consensus rule. Caller-supplied nonzero local peer
identities refer to already authenticated peers; list membership establishes no
finality or preferred-chain authority.

## Contract and completion tests

`app/download_schedule` owns one non-copyable plan with at most 64 distinct peers,
an explicit positive attempt budget and per-peer retry delay. Configure atomically
copies a validated peer list. No allocation precedes its bounds, zero/duplicate
identity and policy checks. Reconfiguration is forbidden while an attempt is held;
otherwise an explicit configure call starts a fresh plan and budget.

One selection scans at most the retained peer count, rotates fairly from the last
selected peer and reserves one private immutable lease before host I/O. All
attempt starts consume budget, including failed stream opens. Cooldown begins at
terminal acknowledgement. Empty responses and failed transport/preparation/adoption
remain retryable under the same bounds; actual canonical adoption completes the
plan. A queued candidate alone is insufficient to report adoption. Backpressure
retains the lease through teardown, preparation and the later service tick.

The host keeps each peer identity stable for the entire plan and retires its
native callback binding before finishing/reconfiguring. The scheduler owns no
native handles and cannot verify native close; the stream controller retains that
lifetime contract. Old, foreign and default certificates cannot acknowledge an
active replacement, including after reconfiguration to the same peer. Nondecreasing
host ticks are required; regression refuses without retiring a lease. Checked
subtraction handles cooldowns near uint64 maximum without wrapping deadlines.
Waiting performs no polling, sleeping, I/O, hashing or producer work. Default and
failed selections contain reasons only; successful/default extraction is guarded.

Require deterministic peer order, exact cooldown boundaries,
all-refused waiting, empty retries, budget exhaustion, adopted completion,
clock regression and maximum ticks, atomic invalid configuration, copied caller
storage, busy reconfiguration and stale/cross-plan leases. Exercise retry scheduling
through real CE 128 failure/empty/healthy transfers to one authenticated fixture
peer, guest preparation and later canonical adoption. Retain privacy/nominal/ownership guards and repeated ARC release.

## Verification

On local macOS with pinned Nimony/ARC, checked optimized Clang/LTO builds:

- `make unit SUITE=application_download_schedule` passes peer rotation, exact
  cooldowns, all 64 peers, full cooling scans, explicit attempt exhaustion,
  maximum ticks, invalid/busy configuration and stale/cross-plan certificates.
  Its 1,000 lifecycle cycles retain 192 occupied bytes before and after.
- `make unit SUITE=application_block_download` passes scheduled real authenticated
  LSQUIC failures, empty replies and healthy transfer, followed by genuine guest
  preparation and later canonical adoption. Reception/callbacks still hash
  nothing; 1,000 receiver lifecycle cycles retain 8,806,720 occupied bytes.
- Three privacy probes, the peer/tick nominal rejection and the actual schedule
  copy-lowering rejection pass. All three strict runtime extraction guards pass
  with their observed AssertionDefect diagnostics; genuine extraction passes its
  positive control.
- Inventory passes with 228 native suites, 159 failure families and 2,019 declared
  probes. All 35 verification tooling tests pass. Pinned Nim/Rust formatting and
  whitespace checks pass.

Evidence is under `build/download-schedule-*` and
`build/tests/native/selected/`. These are local checks; exact-head Linux/full CI
remains separate evidence and is not requested by opening this PR.

## Remaining work

The [joined session owner](application-download-session.md) now binds scheduler
leases to private reception and actual native-close barriers. Production peer-session
catalog wiring, command dispatch and execution workers remain open; no live
production synchronization loop is claimed. Peer authentication, native stream
routing and state adoption retain their existing owners. Durable restart,
consensus and full/light databases remain open. M1 framing is complete; full state
serialization and full JAM/STF parity remain open.
