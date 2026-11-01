# Bounded retained execution memory

An exclusive prepared owner can retain one idle private-memory allocation between calls.
Each new invocation still initializes fresh CPU, paid gas, attempt/callback budgets, host state,
temporary handlers and dirty bitmap. Native code retains no invocation memory pointer; ARM
descriptors are rebuilt from the newly leased byte owners before execution.

## Retention policy and lifetime

`PreparedLimits.retainedMemoryBytes: RetainedMemoryByteLimit` bounds the logical payload of
the immutable baseline plus private region bytes. Zero disables retention. The convenience
`defaultPreparedLimits` selects 64 MiB per prepared identity. Explicit limits constructed without
this field retain their zero/default behavior. The worker cache still retains one prepared
identity and includes this budget in its source/policy key.

All stored baseline pages count, including inaccessible pages that retain payload. Allocator
overhead and mapping metadata are additional; metadata remains bounded by the retained page
count. This is a payload admission limit, not an RSS measurement. `PreparedInfo` copies
`retainedMemoryPayloadBytes` and cumulative `memoryReuses`; diagnostics never authorize execution.
Empty private allocations are not retained. Oversized leases retire normally with no guest refusal.
Eviction or dropping the final prepared handle releases code and idle memory through acyclic ARC.

The lease owns only managed region buffers, copied sorted mapping metadata, one immutable
baseline and dirty physical page ordinals. It holds no CPU, gas, callback, native arena or frame
address. Same-owner synchronous reentry remains refused by the existing exclusive prepared lease.
There is no global memory pool or additional OS allocation interface.

## Restoring complete input

Before reuse, `changedMemoryPageSlots` validates complete owner/count/index/access equivalence
and returns sorted copied slots whose immutable page identity differs. Shared snapshot-directory
blocks skip unchanged work. It allocates no PageImage or copied payload. Existing copied-page
delta behavior remains unchanged.

Only after that preflight, a fresh frame shell consumes the idle buffers and restores the union
of prior guest-dirty pages and changed source slots from the incoming immutable source. Overlap
copies conservatively twice. Every other private byte still equals its baseline page, and shared
immutable page identity proves equal incoming bytes. Mapping/access/count changes release the
rejected idle lease before the ordinary full constructor allocates its successor.

Retaining the frame's actual baseline and dirty set is essential for terminal hosts: a host may
return changed memory without installing it into the stopped resident frame. The returned memory
must not be assumed to describe resident bytes. On the next call, source deltas plus dirty pages
restore it correctly, with fresh construction for changed mappings. Continue responses preserve
the existing checked synchronization and dirty-epoch reset. Local/fallible exits retain no CPU or
callback state and follow the same complete byte-restoration rule if their storage is retained.

## Validation

The registered `pvm_memory_reuse` suite compares full fresh/reused machine snapshots and direct
byte expectations across clean RW/RO source changes, dirty overlap, map/permission/count changes,
interrupted budgets, terminal host responses and fallible reentry. It retains prior outputs to
check immutable ownership. Zero, exact, insufficient and inaccessible-payload budgets are checked,
including worker cache identity. A thousand prepared-owner cycles release all byte leases and
baseline references without increasing occupied ARC memory.

The separate slot suite covers invalid/default/empty owners, shared blocks, equal-byte new page
identity, dense/sparse/partial-tail changes, sorted copied slots and full metadata refusal before
any partial result. Existing prepared opcode parity and independent host reentry also pass with
native-enabled builds: 1,536 host cases, 23,616 callbacks, 17,712 repaired faults, positive native
entry traces and 1,000 ARC cycles. Supported unit runs pass for reuse, slots and prepared blocks.
Every measured public DOOM call validates complete CPU, all page bytes, source and output events;
source roles have identical native activity except compilation time, and interpreted counts are zero.

## Local ARM evidence, 2026-11-01

Apple M1 Max, pinned checked ARC/Clang ThinLTO Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`; shipping baseline
`69a03c9fb9977490c8a5b8a371f0b4cdb50dceb8`. Both roles use common canonical
source/output/cache paths, flags and public drivers. Eight fresh builds pass four duplicate image
controls. Four balanced fresh processes per source role execute 13 prepared public calls;
process medians use samples 3:13 and the table takes the median across processes. Two fresh
PolkaVM interpreted processes provide the raw-call denominator under the established lifecycle.
All restoration and lease return work stays inside public-call clocks.

| Workload/backend | Baseline ms | Candidate ms | Change | Candidate / PolkaVM interpreted |
|---|---:|---:|---:|---:|
| DOOM init JIT | 119.996 | 119.192 | -0.67% | 0.172 |
| DOOM init interpreter | 245.772 | 243.737 | -0.83% | 0.352 |
| DOOM tick JIT | 17.390 | 17.011 | -2.18% | 0.393 |
| DOOM tick interpreter | 24.588 | 24.510 | -0.32% | 0.566 |
| Minimal JIT | 4.242 | 4.229 | -0.29% | 0.691 |
| Pinky JIT | 66.876 | 65.710 | -1.75% | 0.685 |
| Memset JIT | 2.796 | 2.580 | -7.72% | 0.643 |
| Sieve 10m JIT | 216.268 | 210.376 | -2.72% | 0.559 |

All four paired JIT tick directions improve, while aggregate process ranges overlap slightly.
The local interpreter differences are inconclusive. Linux qualification follows below.
Runtime retains additional idle memory within the explicit budget; memory pressure can favor
zero or a smaller limit. Fresh independent source page identities conservatively restore all
changed slots even when bytes happen to match, so the repeated-source results do not establish
the same benefit for every caller pipeline.

An earlier single-executable prototype isolates the buffer policy: JIT tick
17.4065→16.7575ms (-3.73%, nonoverlapping process ranges), with interpreter tick inconclusive.
Twelve reuse receipts per process copy 492 pages across tick reuses and 12,672 across init,
compared with 4,285 accessible pages per fresh call. That prototype materializes page deltas;
the shipping candidate above uses slot-only restoration and explicit retention policy.

Ignored evidence: `build/pvm-memory-reuse-production/shipping-comparison/` and
`build/pvm-memory-reuse/same-image-evidence/`. Shipping raw JSON SHA-256:
`ec2e6261e703726ecb69eb9be17b37b4b0a913d0e7e04e9b8557b707c561f001`.
Policy-control raw JSON SHA-256:
`db68041325f723ea36e581647607ffd459e92c920b3d972e460565506ea1a1ee`.
No compiler, runtime-check, native instruction or guest fixture change is involved.

## Linux ARM qualification, 2026-11-01

The exact runtime head `ffbd8b61d5bb3a359a9aff57d836809c3478ec80` passes the focused
[ARM replay run](https://github.com/jacogr/ragnarok/actions/runs/41305353802), against
`69a03c9fb9977490c8a5b8a371f0b4cdb50dceb8`, with the same pinned checked compiler.
Artifact `13083571684` contains 20 fresh builds, 84 primary processes, 138 positive/refusal
controls and 60 additional JIT replay processes. Author and independent reviewer reparse the
logs, full state/events, 18 image equalities, source/fixture identities and all 14 native-work
pairs. Native counters match except compilation time; interpreted counters remain zero.
Native ownership, memory, dirty regions, partial continuation and priced controls also pass.

Each JIT entry below takes the median of six process medians, each using CPU samples 3:13.
Every paired process improves and baseline/candidate process ranges do not overlap.

| Workload | Baseline JIT ms | Candidate JIT ms | Change |
|---|---:|---:|---:|
| DOOM init | 150.908 | 148.800 | -1.40% |
| DOOM tick | 29.231 | 25.378 | -13.18% |
| Minimal | 5.590 | 5.551 | -0.69% |
| Pinky | 84.449 | 83.500 | -1.12% |
| Sieve 10m | 284.192 | 272.198 | -4.22% |

The primary two-process interpreter comparison gives init 326.171→323.010ms (-0.97%) and
tick 33.706→30.318ms (-10.05%); these have less replication than the JIT replay table.
Matched primary raw-call ratios, ours / PolkaVM interpreted, are **0.631 JIT / 0.755 interpreter**
for tick and **0.238 JIT / 0.517 interpreter** for init. These use primary numerators and their
matching primary reference, not a replay numerator paired with another cohort's denominator.
Primary memset improves 14.88% in JIT and 14.43% in the interpreter; it has no six-process replay.

This supports enabling bounded reuse by default. It retains idle private buffers plus a baseline
reference, trading memory residency for avoiding repeated allocation/copying. DOOM's 4,285
accessible pages charge 35,102,720 logical payload bytes (33.48 MiB) for baseline plus private
bytes, before metadata; shared baseline pages need not represent additional RSS. Zero/smaller
budgets remain appropriate when memory pressure outweighs repeated-invocation savings. Fresh
source identities and mapping changes retain the conservative restoration/fallback behavior
described above. This ARM result establishes no x86 performance claim.

Application report SHA-256:
`dc12cdc2ac89440f8f68b448e991671b495c52345a3d31f52356950f5f3268f9`.
Artifact ZIP SHA-256, independently recorded by review:
`b4089394fb6d0e3db523e187acb8b28d9208facc13e8f64d47b9afd54c2b72de`.
Ignored author audit: `build/pvm-memory-reuse-production/ci-arm-audit.json`.
The final qualification update changes this evidence document only; runtime remains the measured
head above. No additional CI cohort is needed for that documentation change.
