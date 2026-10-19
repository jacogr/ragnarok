# Per-block service activity coordination

## Scope and authority

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
statistics.tex service-statistics equations defining R(s) and the union of newly
reported, provided and accumulated services. Build all eleven service C(13)
fields anew for this block. Refinement counts/metrics come from newly guaranteed
reports, not the newly available or accumulated queue. Preimage extrinsics count
records and payload bytes per service even if later unneeded, following the
existing vector-backed [preimage statistics contract](preimage-transition.md). Preserve each accumulation
(N,T,G) delta exactly. Old per-block service rows never carry forward.

The pure projection accepts immutable reports/preimages and a canonical numeric
sorted unique accumulation-only mapping. Reject unrelated fields, zero deltas,
default/wrong-schema owners and noncanonical keys. Bound reports, digest work,
preimage records/encoded bytes/payload bytes, accumulation rows and retained
services independently before descriptor allocation. Sort fixed candidates and
combine by numeric service; prove every uint64 counter/gas addition before doing
it. CounterOverflow is a local representation refusal, not protocol invalidity.
Return independent caller-owned fixed rows and observations without hashing.

The opaque preparation accepts only genuine finalized accumulation statistics.
Derive the exact incoming verified guarantees and preimage component from its
original retained block; callers cannot substitute reports or provisions from
another block. Check component counts/encoded extent before materializing its
preimage owner. Retain the exact statistics source and immutable coordinated rows.
This proves service metric provenance, not preimage request admissibility or a
complete valid block. It neither integrates preimages nor changes accounts/state.

Completion witnesses cover distinct incoming/accumulated reports, overlapping
and disjoint services, repeated and empty preimages, zero-gas transfers, skipped
code, no old-row retention, exact/short/full-width limits, counter overflow,
copied/detached lifetime, hash-free preparation and 1,000 ARC cycles. Add strict
result/privacy/nominal guards and preserve pinned codec widths. Validator/core
statistics and final C(13) encoding/publication remain separate bounded work.
M1 framing remains complete; full state serialization/block parity remain open.

## Local verification (2026-10-19)

Passed selected native accumulation_statistics, accumulation_reentry_cycle and
report_admission suites with the pinned compiler, checked ARC/Clang LTO and
already prepared crypto/Bandersnatch libraries. All retained fresh 1,000-cycle
ARC evidence with equal occupied memory before/after: 1,307,056, 920,480 and
293,232 bytes respectively. Every new source-derived activity witness also
performs 1,000 preparation cycles with hashing disabled and no retained growth.

Independent pure tuples cover four service identities. Service 42 receives two
refinement contributions (22 gas, 26 imports, 34 extrinsics/38 bytes, 46 exports),
two provisions/two bytes, and its untouched accumulation (2,3,7) delta. Service
77 receives a provision-only tuple, service 88 a failed-refinement-only tuple,
and service 99 a zero-gas transfer-only delta. Every one of the eleven fields is
compared, including explicit unrelated zeros. Empty blobs still count once;
repeated service contributions remain independent records before aggregation.

A genuinely signed child contains one newly incoming guarantee and three
preimage records while its accumulation history processes four original ready
reports. Preparation reports those populations separately, derives the expected
three-service union and counts all provided records/bytes from the exact signed
extrinsic. The detached activity owner retains that source after caller handles
are released. Existing report/transfer/zero-gas/skipped-code/empty activity cases
retain their exact accumulation deltas and prior complete-state identity.

Exact/short/zero/full-width policies, default/wrong-schema owners, duplicate or
descending accumulation keys, unrelated-field/zero-delta refusal, maximum gas,
per-service gas/counter overflow, copied values/observations and nominal bounds
passed. Five strict result guards, three privacy and two nominal compiler
rejections passed with their intended diagnostics; raw finalization/projection
cannot replace finalized statistics. The new module passed semantic compilation.
Nine inventory tooling tests, source-owned inventory, pinned changed-source
formatting, local feature links and whitespace checks passed.

Witness development qualified conflicting codec/enum names and changed compaction
to an indexed loop under the pinned compiler's borrow rules. The regression
selector initially omitted report_admission's required generated fixture; the
existing selected-fixture provider prepared it, retaining the two already-passed
suite results. Logs/results are under ignored `build/pvm-service-activity*`.
No PVM runtime, codec, vendor source, gitlink or dependency pin changed. These are
local macOS checks, distinct from exact-head Linux CI.

Next bounded work: core activity metrics from the original incoming/newly available
report contexts, then validator epoch counters and complete C(13) publication.
Independent account/history/statistics candidates still need coordinated block
publication. M1 framing remains complete; full state serialization/block parity
remain open.
