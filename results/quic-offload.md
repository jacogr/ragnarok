# Bandersnatch offload verification

Observed locally on 2026-10-14, Apple Silicon/macOS, using the existing pinned Nim 2.2.12,
Odin `84bc3fc21`, Rust 1.99.0, historical ark-vrf, SRS, LSQUIC and BoringSSL revisions.
The [workload/ownership contract](../docs/quic-offload.md) identifies the exact GP v0.7.1 and
JAMNP-S references. This is a correctness, responsiveness and lifetime proof; no speed optimization
or language-selection claim is made.

## Observed workload

Both native listeners passed ten same-process waves with two fixed OS workers and four total
retained jobs. Together they completed:

- 60 verified jobs; each checks the official tiny-ring ticket and output through 128 real calls.
- 140 exact cheap CE 143 lookups, including 80 whose response FIN was queued while the native
  worker pool reported an actual verification batch executing.
- 20 capacity rejections, 20 wrong-domain proof rejections, and healthy lookups after each failure.
- 20 queued cancellations, 20 held-running cancellations, and 20 resets during actual crypto
  batches. Queued slots release immediately; running input remains retained until batch completion.
- 20 replacement jobs admitted after queued release, with unique generations and no stale delivery.
- Both completed-capacity selftests: four uncollected verified results reject a fifth job, then
  exactly-once tagged collection frees them. Pending polls have no completion metadata.
- Both held shutdown selftests: two workers and two queued jobs join without deadlocking on the
  test barrier. Both final network shutdowns occur with two real crypto batches and two queued jobs
  pending; all native callbacks and worker setup/input owners retire before the cleanup observation.

Each listener accepted 154 connections, with 150 fully closed at the final wave's idle barrier,
then four pending connections at the explicit shutdown test. Maximum observed overlap was six
connections, with three total OS threads throughout live operation. These are bounded observations,
not identity-based production quotas or a throughput measurement.

## Resource observations

Eight post-warmup idle samples per listener passed the documented fixed budgets. Allocator counts
cover native-language ownership; RSS includes aggregate C/TLS/Rust allocations but is not detailed
backend allocation instrumentation.

| Listener | Peak observed RSS | Idle RSS range | Idle descriptor range | Idle allocation range |
| --- | --- | --- | --- | --- |
| Nim | 14.20 MiB | 240 KiB | 0 | 0 B |
| Odin | 15.31 MiB | 288 KiB | 0 | 0 B |

Nim's final ARC counter was **48 -> 64 bytes**, within its fixed bookkeeping allowance. Odin's
final tracked application allocation and pending nbio operation counts were **0 / 0**. Both
reported two worker joins before final cleanup. No per-peer or per-stream OS thread was created.

## Commands and regressions

Executed:

```sh
python3 tools/format.py
python3 tools/format.py --check
python3 interoperability/test_quic_offload.py --reuse-native
python3 interoperability/test_quic_offload.py --skip-build
python3 interoperability/test_quic.py
python3 interoperability/test_quic_soak.py --skip-build
python3 interoperability/test_quic_mesh.py --skip-build
python3 interoperability/test_quic_service.py --skip-build
python3 interoperability/test_bandersnatch.py
python3 interoperability/test_integration.py --reuse-native
```

The final offload run used independently generated certificates under `build/offload/fixtures`.
The shared fixture helper now accepts a caller-specific folder, preventing another harness from
replacing a retained listener's identity pins. An earlier local overlapping run exposed this
harness collision; isolation fixed it without changing certificate/peer authentication policy.

Regressions passed: the 64-case authentication/protocol matrix, 20,000 DER/frame fuzz cases,
512 idle/ready I/O cancellation checks, 160 lifecycle-soak sessions, 512 retained bidirectional
IPv6 CE queries plus both wrong-identity cases, 32 persistent multi-peer service waves, and 576
integrated codec/hash streams plus its 20,000 capture fuzz cases. The complete Bandersnatch
regression passed its four checked debug/release native suites, published/official vectors,
cross-language proofs, 99 ordinary and 785 ring wrong-width checks, 64 mutated ring proofs and six
negative type probes, including the locked offline Rust build/test and feature guard. Ordinary peers were rebuilt with offload disabled; inspected dynamic
linkage contains no Rust Bandersnatch dependency. Source/toolchain pins and upstream trees are
unchanged.

The Linux workflow now builds labelled offload peers after the pinned native libraries and runs
this same workload. Only explicit logs/summary/resource JSON are uploaded. Linux verification of
this increment awaits the maintainer's pushed run.

## What this establishes

Both candidates can move the pinned Rust RingVRF primitive off their native QUIC dispatcher with
bounded ownership and without a thread per connection/stream. Nim's thread-local ARC setup and
Odin's worker-local default context both pass this slice; the result does not choose a language.

The test uses one independent official tiny-ring ticket and repeats it to establish a compute
window. General scheduling/fairness, full-ring load sizing, independent-stack JAM interoperability,
cryptographic audit/exceptional-point policy, allocator attribution and wider JAM domain integration
remain open. Synchronous Rust cannot be preempted: cancellation suppresses delivery and shutdown
waits for the active bounded batch. Test holds are never counted as actual crypto activity.
