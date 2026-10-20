# Bounded download dispatcher

## Scope and authority

Join the [authenticated peer catalog](application-download-peers.md),
[session](application-download-session.md) and actual Services handoff in a
one-child dispatcher. Preserve GP 0.8.0, recorded vectors and JAMNP-S
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`; no wire or consensus rule changes.

## Contract and completion tests

A non-copyable fixed-address dispatcher owns the catalog/session and borrows one
stable Services owner exclusively until explicit close. Services must outlive
close; callers must not enqueue, take, cancel, close or restart its handoff during
that borrow. Configure explicit peer count/IDs, bounded immutable ancestors,
input/stage/composition policies, stream bounds, retry budget/cooldown and positive
acquisition timeout before opening endpoints. No policies derive from network
input. Stage implementations retain authority over their own execution policies.
Only configured IDs may register endpoints; expected-key pinning and lifetime
rules remain the catalog's responsibility. Endpoint registration/reconnection is
explicit while Waiting with no lease. No automatic address discovery/reconnect.

Each monotonic host tick processes at most one previously queued adoption, polls
each of at most sixteen endpoints nonblockingly once, selects at most one lease,
and prepares at most one candidate after all native callbacks have returned.
Selection, request opening and preparation happen on distinct turns. Complete
input must also cross the real native-close barrier before preparation. A newly
queued candidate cannot publish until a later tick. Only consuming an actual
successful Services adoption result marks Adopted; a real refusal is retained as
a guarded result and retires the attempt as Retry. No caller-provided adoption
acknowledgement exists on this dispatcher surface.

Reject regressing clocks before service/native work. Use elapsed-time subtraction
for the acquisition deadline, covering authentication, pending open and bound stream
closure without overflowing near uint64 maximum. Deadline retirement destroys the
selected native endpoint before releasing its session lease. Stream expiry uses
its independently explicit policy. Once Queued, settlement is separate from the
acquisition deadline: a later tick consumes the real handoff result, without
expiring or re-executing its candidate. Failed/unused input is discarded after close;
valid empty replies keep the healthy connection and enter scheduler cooldown.
Retries retain the same finite budget. Exhausted is distinct from Adopted.

Reject a foreign pending/finished handoff without processing or taking it. An
externally cancelled/taken queued job is LostHandoff and can never imply adoption;
this detects a violated borrow rather than providing concurrent-producer support.
The exclusive borrow remains required even though some violations are detected.
Shutdown retires native callbacks first, cancels its unattempted queued candidate,
or retains its actual externally processed result, then ends the Services borrow.
It neither executes queued work nor consumes another producer's result.

Completion witnesses use real TLS and a genuinely signed candidate: target
isolation, unchanged canonical snapshot at Queued, later actual adoption/refusal,
empty cooldown/exhaustion, missing-handshake deadline near uint64 maximum,
body-without-FIN retirement, startup preflight, foreign handoff backpressure,
lost-handoff refusal, queued shutdown, 1,000 ARC cycles and private/copy/runtime
contracts. Existing session/catalog tests retain callback-only hashing evidence.

## Verification

Local pinned Nimony/ARC checked optimized Clang/LTO evidence:

- The selected native dispatcher suite passes real TLS target isolation, separate
  preparation/adoption, actual adoption refusal, empty reply cooldown/exhaustion,
  missing-handshake deadlines near uint64 maximum, body-without-FIN retirement,
  startup preflight, foreign/lost handoffs and queued shutdown.
- The affected `application_download_peers` Make suite also passes, with 1,000
  real endpoint cycles retaining 8,803,968 occupied bytes before and after.
- 1,000 real endpoint opens, selected leases and canonical Services retirements
  retain exactly 132,288 occupied bytes before and after.
- The 56 native fixture harness, 35 verification harness and 11 inventory harness
  tests pass.
- Privacy, nominal-clock and actual composite-copy lowering rejections pass.
  Default adoption extraction and forgotten-close runtime guards require the
  exact observed contract diagnostic, exit one and AssertionDefect; the genuine
  explicit-close positive control passes.
- Final pinned formatting, inventory, feature links and whitespace checks pass.
  Inventory discovers 231 native suites, 162 failure families and 2,029 probes.

Evidence is under `build/download-loop-*` and `build/tests/native/selected/`.
These are local macOS checks; exact-head Linux/full CI is separate evidence.

## Remaining work

Explicit command-line endpoint/state-stage policy loading and production command
wiring remain the next bounded increment. Preparation remains synchronous between
callbacks; a bounded execution worker is still needed before production load.
This is a dispatcher API, not a launched synchronization service or fork choice.
M1 framing is complete; full state serialization/JAM parity, persistence and
separate full/light databases remain open.
