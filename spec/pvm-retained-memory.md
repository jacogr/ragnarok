# Bounded retained execution memory

An exclusive prepared owner can retain one idle private-memory allocation between calls.
Each new invocation still initializes fresh CPU, paid gas, attempt/callback budgets, host state,
temporary handlers. The idle lease can also retain a dirty bitmap, but every execution
starts with its bits cleared after input restoration. Native code retains no invocation memory
pointer; ARM descriptors are rebuilt from the newly leased byte owners before execution.

## Physical dirty-bitmap extent

A fresh frame allocates absolute physical-page bits through the highest sorted admitted description,
including read-only and inaccessible pages. Empty maps allocate no words; other maps allocate
`(uint64(last.index) shr 6)+1` words, at most 16,384 words (128 KiB). Low maps avoid unused trailing
words without changing store indexing, frame layout or native descriptor ABI. High stack maps retain
the full extent. Native descriptors borrow the actual word count. Unknown or short metadata keeps
conservative publication/restoration behavior.

Same-map scratch reuse moves the existing bitmap and clears its dirty epoch after byte restoration.
Mapping or permission changes rebuild the frame and bitmap together, including host responses which
add high pages. The retained-memory suite covers physical pages 63/64 across a store, dense publication
with high read-only/inaccessible observations, and a low-to-high host remap followed by a store to
address `0xfffffffe`, repeated scratch reuse and immutable predecessor checks.

Local checked ARC/Clang qualification on macOS ARM64 passes the retained-memory suite (including
1,000 unchanged-allocation ARC cycles), scalar memory boundaries, host resume, region/host lifecycle,
real ARM macro capacity and shared-worker suites. The existing ARM ThinLTO correctness witness also
passes dirty/word, memory/resident cycle and macro controls. Generated hot C and retained Frame/scratch
declarations preserve the existing layout/indexing contract; this is not x86 native execution proof.
The new highest-page fixture uses `0xfffffffe`: the existing exclusive-end rule still traps at
`0xffffffff`, as covered by the unchanged scalar boundary suite.

Reduced allocation extent is deterministic; its contribution to cold CPU cost remains unproved.
Existing high-stack `memset` maps receive no bitmap reduction. No timing cohort or bitmap CI has run.

## Managed region fill before publication

The qualified managed-fill parent allocates uninitialized private bytes inside `buildFlatFrame`. Each admitted
adjacent run has one access mode; the constructor copies every complete 4 KiB source page into its
disjoint output span before adding the region or deriving any Frame/native view. Inaccessible pages
allocate no region. The source owner and layout remain immutable throughout the copy.

This local fill-before-publication rule preserves completed-buffer ownership for `RWStorage`,
retained scratch and transactional host replacement. It uses the same pinned allocator, size bounds,
heap caps and OOM policy; the resident first-RW zero-provenance path is unchanged. Byte payload has
no resource destructor. Local checked ARC/Clang ThinLTO C inspection confirms direct metadata
transfer, cleanup without payload reads and complete page writes before publication, including
the intervening region-ref allocation and its terminating failure path. The managed allocation's
default-fill loop is absent; unrelated sequence initialization remains unchanged.

The isolated prototype on scalar-host tip `1708cbea` passes the existing complete-page canary,
map, host-remap, sparse, memory-reuse, fresh-resident and mixed-scalar suites, plus ARM macro-capacity
and shared-worker consumers. Fresh 1,000-cycle ARC observations remain unchanged for memory reuse,
fresh-resident and mixed-scalar execution. The actual ARM ThinLTO witness and maintained native
receipt validators pass. Retained Frame/scratch C declarations match the earlier bitmap witness;
104 common hot C functions match after local-variable/label renaming. This comparison does not
establish whole linked-image equivalence or x86 native execution.

The existing `nimMaxHeap=67108864` compatibility profile also passes its complete-byte and fresh
ARC checks. The pinned runtime interprets that value in MiB, so this proves managed-path selection
and preserved cap dispatch, not a 64 MiB pressure/refusal test. No timing or CI qualification has run
for this prototype. The observed zero-then-copy pattern motivates the change; unqualified diagnostic
counts establish no CPU dominance or speedup.

## Local lazy EXTRA payload prototype

The separate prototype based on `70a59bbb` leaves primary RO/RW/stack payload construction and
native descriptors unchanged. Additional fragmented regions retain their positive logical extent,
access and genuine sorted source-slot range under the containing Frame's immutable `sourceMemory`.
An empty EXTRA payload reads that baseline; a materialized payload owns the complete logical run.
Scratch retains the same source owner and coordinates. No borrowed page pointer, new extraction
API, content fingerprint or caller freshness promise is introduced.

Slow loads still perform the complete canonical scalar preflight. Its returned baseline bytes
are overlaid with any current private bytes. Publication fallback and independent complete-byte
checking use their existing copied source page for the same overlay; final-address and inaccessible
payload observations remain complete. Holes remain unmapped. Untouched extras remain absent from
dirty-only publication and preserve the immutable baseline directly.

A slow store first completes the unchanged whole-width page/permission preflight. Only then may it
allocate a full EXTRA temporary, copy every source page, install the completed payload, mark dirty
pages and mutate guest bytes. Adjacent pages with equal access are one captured run, so a successful
scalar store of at most eight bytes cannot span distinct regions; a hole/permission boundary fails
before materialization. Repeated stores reuse the completed buffer. No allocation occurs inside
the per-byte setter. Ordinary managed payload OOM is deliberately deferred from construction to
first write. This local physical-allocation timing tradeoff adds no recoverable-OOM contract and
does not change selected resident-allocation refusal or canonical gas/attempt/fault precedence.

Reset and same-map reuse restore complete materialized pages for the existing dirty/changed-source
union. Baseline-backed extras follow the admitted incoming owner without private copying. Complete
map/access equality precedes source rebasing; remaps and permission changes still rebuild a complete
logical frame transactionally before moving caches or committing. Scalar host replies retain old
baseline and dirty membership. Owned host replies preflight every changed logical destination before
applying any private copy, then commit the posterior source owner and clear dirty state. Lazy extras
accept that new owner without allocation; materialized writable extras receive full changed pages.
Selected fresh-RW refusal still preserves the old stopped frame and all repair/retry observations.

`flatHostStats`' third diagnostic now counts actual full-page copies during accepted same-map host
updates. Previously it counted accepted changed slots, which coincided with physical copies while
all extras were eager. A baseline-backed extra update now contributes zero; a materialized update
contributes one per copied page. Destination validity remains a separate boolean and a zero-copy
accepted change is not a refusal. Existing primary-update counter expectations are unchanged.

Retention continues to charge every EXTRA's full logical extent, including unmaterialized payloads,
plus all stored baseline pages. Zero disables retention and an oversized idle lease retires without
guest refusal. This conservative logical charge does not claim RSS or physically allocated bytes.
The existing resource-boundary suite gains one complete-page host/store/scalar/scratch lifecycle
case with nonzero canaries, cross-page EXTRA writes, immutable predecessor snapshots, unchanged
RO/inaccessible payloads, an unmapped hole, incoming source rebasing and literal copy-count checks.
All existing byte, map, source, alias, capacity and resident-refusal oracles remain unchanged.

Local macOS ARM64 checked qualification passes seven existing correctness suites:
`pvm_stream_resource_boundary`, `pvm_memory_reuse`, `pvm_stream_regions_and_host`,
`pvm_fresh_resident`, `pvm_scalar_host`, `pvm_jit_memory_rules` and `pvm_shared_async_arm`.
The changed resource-boundary image passes its exact registered output under ARC/Clang/ThinLTO;
the other suites use their unchanged maintained profiles. Fresh 1,000-cycle ARC observations for
memory reuse, fresh resident and scalar host return to their baseline allocation counts. The shared
ARM positive receipt records one submitted/completed fragment, three native calls and 18,432 native
operations. Bare-frame memory-rule checks remain separate from this actual native-entry evidence.

Generated C inspection found and corrected a first-write allocation-refusal gap: the pinned managed
sequence allocator may return empty bytes after reporting OOM. An explicit actual-length assertion
now precedes every output span, source copy and payload installation in all four scalar widths in
both resource-boundary and canonical ARM images. This restores the existing controlled fatal/assertion
boundary without claiming recoverable whole-call OOM. No forced-refusal or heap-pressure profile ran.
The first guest run also exposed an invalid new hole oracle: an absent in-domain `pageImage` succeeds
with an inaccessible zero page. The corrected witness checks that complete representation and a
canonical load fault with the exact aligned page. Earlier failure outputs and images remain preserved;
the first bare assertion output alone does not uniquely locate every possible failing assertion.

Canonical generated Frame/scratch/RW-view declarations and primary/native descriptor paths retain
their recorded layout/source contract. EXTRA descriptors gain two integer coordinates, including
temporary primary construction wrappers, so this is not a claim of zero metadata cost. The source
owner, complete byte checks and conservative logical retention bill remain unchanged. This is bounded
local correctness evidence, not Linux/x86 qualification, linked-image equivalence or a performance
result. The canonical producer was built but never executed; no timing cohort or CI ran.

For the existing sparse kind4 fixture only, 62 untouched two-page EXTRA runs omit 62 private payload
allocations and 124 source-page copies (507,904 bytes / 496 KiB). Both primary runs, all 128 immutable
source pages, metadata, logical retention charges and complete canary checks remain. Actual latency
benefit remains unmeasured; source-work counts alone do not establish one.

## Retention policy and lifetime

`PreparedLimits.retainedMemoryBytes: RetainedMemoryByteLimit` bounds the logical payload of
the immutable baseline plus complete logical private region extents, including lazy EXTRA payloads.
Zero disables retention. The convenience
`defaultPreparedLimits` selects 64 MiB per prepared identity. Explicit limits constructed without
this field retain their zero/default behavior. The worker cache still retains one prepared
identity and includes this budget in its source/policy key.

All stored baseline pages count, including inaccessible pages that retain payload. Allocator
overhead and mapping metadata are additional. A nonempty idle lease can retain one fixed
128 KiB dirty bitmap and an index sequence requested with capacity for at most one `uint32`
per retained page (four logical bytes per page). Allocator capacity rounding and bookkeeping
are additional. Neither metadata allocation enters the reported logical payload or makes its
limit an RSS bound. Both are released with the lease. `PreparedInfo` copies
`retainedMemoryPayloadBytes` and cumulative `memoryReuses`; diagnostics never authorize execution.
Empty private allocations are not retained. Oversized leases retire normally with no guest refusal.
Eviction or dropping the final prepared handle releases code and idle memory through acyclic ARC.

The lease owns managed region buffers and, when selected, one exclusive mapped RW buffer,
copied sorted mapping metadata, one immutable baseline, dirty physical page ordinals and
their bounded bitmap. It holds no CPU, gas, callback,
native arena or frame address. Same-owner synchronous reentry remains refused by the existing
exclusive prepared lease.
There is no global memory pool. The optional fresh-RW mapping is owned and released by the
private resident-storage boundary described below.

## Fresh first-RW capture

The first contiguous writable run is classified before any region byte allocation. A private
factory may use fresh anonymous read/write storage when the immutable source proves at least
256 complete pages zero (an initial unmeasured 1 MiB selection bound). It validates the entire
run's owner, sorted positions, physical adjacency and permission before allocation. It skips
only whole pages with genuine construction provenance and copies every unknown page, including
mixed initialized prefixes, before returning a complete owner. No caller freshness promise,
content scan, old full RW sequence allocation or post-refusal managed retry is used.

This path requires the standard native allocator on a 64-bit Linux/macOS profile. Any presence
of `nimMaxHeap` or `nimHardenOutOfMem`, including zero/false definitions, selects the existing
managed path. Mimalloc, libc allocator, no-libc and unsupported profiles also remain managed.
These are compatibility guards; there is no new aggregate cap, quota, CLI or accounting domain.
Dense/imported sources without sufficient provenance retain complete managed construction.

A length-first pointer/length view occupies the RW access slot, while a cold exclusive
Empty/Managed/Resident owner controls retirement. Access, slicing and native descriptors inspect
only that view, with the existing bounds and permission guards. RO, stack and fragmented regions
remain managed. The view never owns storage or enters an asynchronous code cache. Actual layout
and lowering require checked validation; the type declaration alone proves no ABI result.

Full logical private bytes and all baseline pages still enter the existing retention bill.
A mapped owner additionally retains its complete original rounded release span until unmap;
these extents are neither RSS nor managed-heap statistics. Ownership moves intact through active
frames and idle scratch. Destination views/descriptors derive from final storage; moved-source
RW and cached ARM/read contexts are disarmed, including manual child transfers to scratch.
Frame, success-wrapper and actual scratch heap payloads reject copying in interpreted and native
profiles. Compiler-generated aggregate destruction retires all remaining managed/native children.

A selected OS allocation refusal returns `ResidentAllocationRefused` through preparation,
ordinary/single-step/host execution and replacement. It is a local failure, with no guest trap,
gas outcome or malformed-program/host-response substitution. Replacement constructs completely
before moving code caches or committing, so refusal preserves the old stopped frame and its
CPU, bytes, counters and descriptors. A mismatched idle lease is discarded before fresh
construction as before. Managed metadata allocation retains its existing OOM behavior; this
change does not claim whole-call OOM recovery.

Full-page reset, dirty/changed-source reuse and host updates always restore complete source
bytes even when the allocation was initially zero. Fresh-zero authority ends at construction;
allocation origin never licenses skipping a later overwrite or inferring access permission.

Focused maintained coverage is owned by `pvm_resident_bytes` (storage/layout/release) and
`pvm_fresh_resident` (mixed-prefix Frame construction, dense fallback, complete dirty/changed
restore, exact retention boundary, allocation refusal and stopped-host rollback). Both include
1,000-cycle ARC/lifetime workloads with separate mapped-extent observations. Source-owned
ordinary-assignment guards cover actual owning resources, Frame/results and the scratch heap
payload. Existing memory/host/native lifecycle suites remain required. Local correctness and
lowering evidence must precede performance claims; prior timing tables below describe their
historical managed implementations, not this new allocation path.

### Validation and performance status, 2026-11-07

The local base is `e16e9bd02a1b7beac9ba1f322a6d44c991d01231`. The corrected feature passes
thirteen affected maintained application suites, the owner suite, and fourteen exact
ownership-copy refusals under pinned checked ARC/Clang. Calibrated AddressSanitizer runs of the
unchanged owner and application suites also pass. Each suite completes 1,000 ownership cycles:
managed occupancy stays 192 bytes for the owner and 24,896 bytes for the application, alongside
balanced logical/mapped extent observations. These are scoped correctness results, not RSS or
allocation-cap measurements.

The unchanged application also passes ThinLTO builds with ARM and x86 native include profiles,
and with a 64 MiB managed-heap cap. The host is macOS ARM64; the x86-enabled result establishes
compilation and portable application behavior, not native x86 execution. Actual ARM C layout
preserves all 53 prior Frame field offsets and all 12 scratch offsets. Cold ownership adds
32 bytes at the end: Frame 3,032 to 3,064 bytes, scratch 152 to 184 bytes. The RW view remains
16 bytes, with length at offset zero and pointer at offset eight. Variant reset hooks select
payload-free neutral tags using writes only because the pinned compiler also calls them on
uninitialized storage; live-value destruction still follows the valid active tag.

The single local paired performance screen stopped at its first baseline synthetic interpreted
positive control: `arithmetic-1`, sample 1, reported CPU 0 ns and wall 417 ns, then the existing
execution CPU clock-resolution assertion failed. Three baseline images had linked; no candidate
image or A/B timing process ran. The failure and raw transcript are retained without a retry,
filter or clock-threshold change. This establishes no performance result for resident storage.
Performance remains on hold pending the exact-head canonical Linux ARM64/x86-64 `bench-pvm`
report and its retained control/native/state evidence. The 256-page selection bound remains
experimental. Historical timing tables below do not qualify this new path.

Post-rollback local validation at `01608aa7d` merges the reviewed published compiler rollback,
restoring native `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` and the original browser pin.
A private official SDK passes the canonical `make check-pvm-native` path, including actual ARM64
native execution, forced refusals, shared lifecycle checks and both resident suites with fresh
ARC evidence. The targeted `pvm_machine` and `pvm_memory_directory` suites also pass.

An independent source/type/compiler audit retains the earlier corrected ownership-copy guards,
calibrated owner/application ASan, and C reset/layout results as bounded equivalent coverage.
Only upstream same-domain PageIndex/CodeAddress equality and an equivalent converted-opcode ARM
membership proof differ in PVM production source. Owning/reset/view/native-adapter bodies, types
and relevant profiles are unchanged. The retained results are not newly generated exact-head
binaries or native Linux execution. Final publication qualification still requires the canonical
report from both Linux architectures at the final candidate head.

## Restoring complete input

Before reuse, `changedMemoryPageSlots` validates complete owner/count/index/access equivalence
and returns sorted copied slots whose immutable page identity differs. Shared snapshot-directory
blocks skip unchanged work. It allocates no PageImage or copied payload. Existing copied-page
delta behavior remains unchanged.

Only after that preflight, a fresh frame shell consumes the idle buffers and restores the union
of prior guest-dirty pages and changed source slots from the incoming immutable source. Dirty
physical pages restore first. Each changed slot then resolves its physical page and checks the
still-live dirty bitmap: only a bounded set bit proves that the first loop already restored it.
An absent or short bitmap cannot prove overlap, so the changed page keeps its source copy. The
bitmap clears only after both loops. Every other private byte still equals its baseline page, and shared
immutable page identity proves equal incoming bytes. Mapping/access/count changes release the
rejected idle lease before the ordinary full constructor allocates its successor.

For dirty physical pages D and accessible changed physical pages C, this avoids one 4,096-byte
restore for each page in their intersection. Changed-only rows retain their full copy and gain a
membership check. This bounds avoided copy demand, not net execution time; an unchanged incoming
owner has an empty changed-slot list.

Retaining the frame's actual baseline and dirty set is essential for terminal hosts: a host may
return changed memory without installing it into the stopped resident frame. The returned memory
must not be assumed to describe resident bytes. On the next call, source deltas plus dirty pages
restore it correctly, with fresh construction for changed mappings. Continue responses preserve
the existing checked synchronization and dirty-epoch reset. Local/fallible exits retain no CPU or
callback state and follow the same complete byte-restoration rule if their storage is retained.

## Plain prepared frame lifetime

See the [prepared frame routines](../src/pvm/step.nim#L563) and the
[cross-page reuse regression](../tests/unit/codec/test_pvm_memory_reuse.nim#L151).

## Validation

The registered `pvm_memory_reuse` suite compares full fresh/reused machine snapshots and direct
byte expectations across clean RW/RO source changes, dirty overlap, map/permission/count changes,
interrupted budgets, terminal host responses and fallible reentry. It retains prior outputs to
check immutable ownership. Zero, exact, insufficient and inaccessible-payload budgets are checked,
including worker cache identity. A thousand prepared-owner cycles release all byte leases and
baseline references without increasing occupied ARC memory.

A sparse 65-page read-only continuation distinguishes dirty physical pages 63/64 at slots 0/1
from changed-only physical pages 189/190 at slots 63/64. Literal register expectations consume
incoming overlap, fragmented RW/RO and untouched bytes, independently of snapshot publication.
Exact and equal-byte source owners, unpublished stores, same-count physical remapping, access
changes, count changes and retained inputs/outputs also preserve fresh-execution behavior.

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
Primary memset improves 14.66% in JIT and 15.96% in the interpreter; it has no six-process replay.

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
