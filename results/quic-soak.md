# QUIC lifecycle soak — 2026-10-14

Historical report: this describes the earlier dependency/wrapper approach.
The active implementation now uses [explicit adapters without Nim source
patches](quic-adapters.md). The observations below retain their original scope.

The bounded soak passes on Apple Silicon macOS for both implementations and all
cross-language combinations. Linux CI includes the same test; its first run stopped on a harness readiness
check after one successful session. Full Linux soak verification awaits a rerun. No language is selected and M3 remains open.

## Executed verification

Using Nim 2.2.12 with ARC, Odin dev-2026-10:84bc3fc21, the existing pinned native
dependencies and debug/native proof build flags:

```sh
python3 tools/format.py
python3 interoperability/test_quic.py
python3 interoperability/test_quic_soak.py --skip-build
python3 tools/format.py --check
```

The original native fuzz checks and 64-case peer/rejection matrix pass.
The soak passes 40 sessions per pairing, 160 sessions total, retaining the same
native processes across their engine/socket/connection lifecycles. It verifies
800 healthy replies, 160 cancellations with pending large writes, 160 malformed
stream-kind rejections and 160 missing-FIN deadlines. Healthy requests continue
on the same connection after failures. Every session demonstrates a pending
flow-controlled write followed by successful large-payload consumption.

The workload, 1 MiB fixture, 64 KiB stream credit and hard acceptance budgets are
[documented separately](../docs/quic-soak.md). These are test policy, not new
protocol requirements. JAMNP-S remains pinned to
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, **Protocols and streams**, **Messages**,
**Notation**, and **CE 143: Preimage request**; all compiler/source pins remain.

## Resource observations

Values below are server/client, after eight warmup sessions for idle ranges.
Every observed peer has one OS thread. Idle descriptor variation is zero for
all peers. Odin's tracked application ownership returns to its exact baseline
on every round. Nim live-allocation variation stays at or below 128 bytes.

| Server | Client | Peak RSS, MiB | Idle RSS range, KiB | Live allocation range, bytes |
| --- | --- | --- | --- | --- |
| nim | nim | 9.52 / 9.27 | 208 / 64 | 0 / 0 |
| odin | odin | 10.88 / 8.84 | 2448 / 2480 | 0 / 0 |
| nim | odin | 9.52 / 10.25 | 144 / 2608 | 64 / 0 |
| odin | nim | 9.83 / 9.22 | 368 / 80 | 0 / 128 |

[Full observations](quic-soak-macos.json) retain each idle snapshot, peaks and
limits. RSS includes allocator reserves and C/TLS allocations; the language
allocation counters exclude C/TLS internals. Sampling and gate overhead are
included in elapsed times, so these measurements are not throughput benchmarks.

## Lifetime fixes exposed by the test

The first RSS-only run stayed within its 16 MiB budget but retained approximately
153 KiB of live Nim allocations each session. Adding allocator counters made
that run fail the stricter 64 KiB live-allocation range budget. The fix captures
certificate-verifier inputs in a separate ordinary function, clears the stopped
context's timer ownership, and releases the UDP transport after awaited close.
The retained-growth pattern disappears in the final run.

The dependency changes are the reviewed
`lsquic-arc-context-cleanup.patch` (removed from the active build; retained in Git history),
applied idempotently by the existing build runner. Together with the two earlier
patches, this keeps the maintained wrapper on its original pinned revision.
Patch application and idempotence were verified. No tracing GC is introduced.

Odin now forwards transport reset/STOP_SENDING notifications and flushes buffered
request bytes independently of FIN. Its stream buffers have explicit bounded
allocation and close-callback release; local deadlines and malformed streams
settle their own handlers while the other streams continue. Both native owners
are retained until callbacks finish, including cancellation and shutdown.

## Remaining limits

This is a finite IPv4 loopback lifecycle regression. It recreates an engine per
session and exercises one connection per engine, not a long-lived multi-peer
service. Longer-duration runs, persistent-engine reconnection, concurrent
connections, IPv6, independent-peer interoperability and C/TLS allocation
instrumentation remain further M3 work. The Nim connection callback cycle warning
is still emitted by the pinned wrapper; native shutdown clears that callback,
and the measured lifecycle budget passes, but this finite test is not a proof
of leak freedom for all wrapper paths.

Wait for the maintainer's next bounded increment before expanding the prototype.

## Linux readiness follow-up

[Run 38516397033](https://github.com/jacogr/ragnarok/actions/runs/38516397033)
passed codec conformance and the original QUIC suite. Its first Nim/Nim soak
session also completed, including the mixed stream workload and cleanup. On
the second session, a receive-buffer warning appeared between `SESSION_DONE 0`
and `READY`. The harness waited for those lines to be adjacent and never
released the client's dial; the ready server eventually hit its authentication
deadline. The warning was diagnostic output, not the transport failure.

Readiness now counts exact complete `READY` lines for the requested round.
Completion markers also match complete lines, so session 10 cannot satisfy
session 1. Five harness regression tests cover interleaved warnings, stale
readiness, misleading marker substrings, resource ceilings and progress
deadlines. The budgets, native implementations and socket settings are unchanged.

Verification after the harness fix: all five regression tests and the full
160-session macOS soak pass. Formatting, actionlint and `git diff --check` also
pass. The next Linux run remains the verification for the CI correction.

## Linux receive-cancellation follow-up

[Run 38517282183](https://github.com/jacogr/ragnarok/actions/runs/38517282183)
passed the full 40-session Nim/Nim pairing and its resource budgets. Odin/Odin
then failed during its eighth session with
`core:nbio/impl_linux.odin` reporting `unexpected nbio.link_timeout() error`.
The diagnostic does not include the underlying errno; no specific kernel error
is assumed.

The proof used a 20 ms linked timeout on every UDP receive only to bound shutdown
latency. It now retains an untimed receive operation explicitly. Standalone QUIC
timers and the event-loop tick still drive session/stream deadlines. Shutdown
removes the outstanding receive, suppresses any queued callback, and drains
cancellation while the owning buffer remains alive. Compiler and dependency
pins, protocol deadlines and resource budgets are unchanged.

A native regression test exercises 256 idle/ready receive cancellations with
exact callback suppression and allocator cleanup checks. It runs in the shared
QUIC suite on both macOS and Linux CI. Full Linux soak confirmation awaits the
next run.

Local verification after explicit cancellation: all 256 native cancellation
cases, the original 64-case QUIC suite, the full 160-session soak, five harness
regression tests, formatting and `git diff --check` pass on macOS. The Linux
backend will execute the native cancellation regression in the next CI run.

## Linux dispatcher ownership follow-up

[Run 38518614775](https://github.com/jacogr/ragnarok/actions/runs/38518614775)
failed in the new cancellation selftest at event-loop acquisition. The assertion
did not include its iteration or the returned error, so the precise kernel or
allocator failure cannot be identified from that log. It failed before the
network matrix and soak ran.

The selftest had initialized and destroyed 256 event loops in rapid succession,
with the tracking allocator installed before initialization. It now acquires
one process-lived dispatcher using the normal allocator, then repeats the
256 socket/receive cancellation cases within that loop. Odin's soak also holds
one dispatcher for its process lifetime; each session's nested acquisition
borrows it. Engines, connections, sockets and operation owners still retire
between sessions, while dispatcher pools remain process-owned and are covered
by the RSS and descriptor budgets. Application ownership remains tracked.

Initialization failures now print their actual platform error and return failure
rather than hiding it behind an assertion. Cancellation checks also require
zero pending user operations after every case. CI retains process resource
limits in the platform log. No initialization retry, kernel limit increase or
resource-budget relaxation is added. Linux confirmation awaits the rerun.

Local verification after dispatcher lifetime changes passes: 256 cancellation
cases, the original 64-case QUIC suite, the full 160-session soak, five harness
regression tests, formatting, actionlint and `git diff --check`. Linux startup
and the full soak still require confirmation in the next CI run.
