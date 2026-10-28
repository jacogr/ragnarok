# Transactional ARM pure-prefix byte store

## Scope

Isolated draft experiment above the accepted scalar source matcher. The existing
DOOM profile identifies indirect byte store opcode120 as a substantial remaining
checked-handler cost. Admit at least three pure operations plus one terminal byte
store, total at most64, within a single already reserved source block. Headers,
branches, earlier memory/host/exit operations are never crossed. Other store widths,
read admission and source/gas policies remain unchanged. No timing claim yet.

The existing X4..X16 guest bank retains the speculative prefix. Fresh invocation-owned
72-byte descriptors contain only genuine stack/RW full-byte extents and the dirty
bitmap word extent; code caches retain no pointer. Native effective addresses wrap
modulo32, then conservatively retain the checked worker's protected/top-address slow
path. All writable and dirty-word guards precede every register, byte or dirty-bit
mutation. A refusal returns flatStop, publishes nothing and replays the original
prefix. Success marks the exact page, stores one low byte, publishes dirty registers
and returns the captured source successor. No byte can cross a page boundary.

Pointer scratch uses caller-saved D0 by integer bit transfer only; no FP arithmetic,
X18, callee-saved register or new OS/FFI ABI. Frame creation/remap rebuilds descriptors;
reset/host deltas mutate stable allocations, while immutable source snapshots and
checked publication remain authoritative. The same native cache/page/word ceilings
and source budget/gas checks remain enabled.

## Checks and verdict gate

Direct native literals cover all13x13 value/address aliases, derived prefix values,
both writable roles, protected/top/wrapped/full64 addresses, extent refusal, absent
writable/dirty regions and page/bitmap-word boundaries. Every register, byte and dirty
word is compared on success/refusal. Native refusal controls execute no direct cases.
Integrated independent single-step cases check every prefix budget, paid/unpaid gas,
RO/inaccessible/extra/empty/high-page maps, host publication, cache transfer and memory
replacement. The shared oracle now compares stores against its immutable single-step
memory snapshot and separately proves the original input snapshot remains unchanged.

All native compilation/execution/timing is CI-only. Require complete exact-head
native gates and seven-workload paired public/core/reference cohorts, constructors,
cold/reused scopes, both orders and calibrated profiles. Keep only useful benefit
without material regressions; otherwise restore just this runtime change while
retaining meaningful witnesses/evidence. Simulated misses are not hardware counters.


## First admission verdict: reject the narrow prefix-only rule

[Run40759906674](https://github.com/jacogr/ragnarok/actions/runs/40759906674)
measured `a45f5fde62c8bae4b6da012c6943e89c1750916b` against accepted parent
`a228c0bc0581f491cbd98d393575c6ae3fe7bd84`, one Linux ARM64 runner reporting
`aarch64`, pinned October28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`.
All9 native gates/2policies,3,380 exact native register/byte/dirty-bit literals and
10,976 source/gas/host/remap controls per witness build passed. Independent artifact
audits passed70 processes/910 checked calls,115 positive/refusal controls,16 fresh
builds/eight equal-image pairs, full reference states/source snapshots/ordered host
events, six calibrated cold/reused profiles/78 calls and eight fresh diagnostic
builds/four equal-image pairs. No hardware counters/cache simulation were collected.

CPU milliseconds forward/reverse, reused medians of samples1..12. Reference call
excludes restoration/teardown; constructors, cold calls and retained core/publication
remain distinct. This is measured rejection evidence, not a retained speedup.

| Workload | Accepted reused | Prefix-only reused | PolkaVM interpreted call |
| --- | ---: | ---: | ---: |
| Sieve100k | 2.996/2.965 | 2.950/2.948 | 6.026/6.045 |
| Minimal100k | 5.984/6.253 | 6.311/6.159 | 5.520/5.543 |
| Memory fill100k | 4.561/4.476 | 4.584/4.514 | 3.743/3.765 |
| Pinky | 87.032/86.995 | 87.313/87.878 | 87.626/87.901 |
| Sieve10m | 284.461/285.338 | 281.523/280.974 | 333.726/333.737 |
| DOOM initialization | 325.245/321.604 | 320.213/329.102 | 627.638/627.719 |
| DOOM gameplay | 46.657/46.755 | 46.310/46.032 | 40.101/40.082 |

| Workload | Accepted constructor | Prefix-only constructor | Accepted cold | Prefix-only cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 3.020/2.952 | 2.923/3.051 | 10.646/10.533 | 10.503/10.667 |
| Minimal100k | 0.018/0.016 | 0.015/0.015 | 6.234/6.191 | 6.387/6.438 |
| Memory fill100k | 0.054/0.055 | 0.057/0.056 | 8.905/8.212 | 8.864/8.091 |
| Pinky | 0.733/0.744 | 0.724/0.745 | 91.254/91.129 | 91.470/92.165 |
| Sieve10m | 3.039/3.046 | 3.171/3.461 | 291.228/291.750 | 289.314/288.226 |
| DOOM initialization | 8.736/8.556 | 9.369/8.762 | 353.445/346.797 | 351.066/353.882 |
| DOOM gameplay | 8.662/8.594 | 8.772/8.910 | 65.700/64.683 | 65.210/64.873 |

| Scope | Accepted Ir | Prefix-only Ir | Accepted conditional/indirect simulated misses | Prefix-only conditional/indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve cold | 113,774,095 | 113,762,351 | 1,059,322/429,279 | 813,989/429,289 |
| sieve reused | 46,638,431 | 46,638,470 | 215,948/395,198 | 57,961/395,198 |
| init cold | 3,341,188,250 | 3,341,774,473 | 3,580,299/23,991,123 | 2,795,477/23,918,668 |
| init reused | 3,238,314,250 | 3,238,324,183 | 2,162,754/23,899,878 | 1,373,531/23,826,893 |
| tick cold | 645,069,336 | 645,141,497 | 1,963,972/8,549,435 | 1,026,631/8,548,721 |
| tick reused | 616,325,358 | 616,326,176 | 1,565,075/8,523,586 | 625,538/8,522,812 |

The guard works, but the rule barely reaches gameplay:26 extra native span calls
per invocation,169 extra lowered operations and four extra fragments. Reused generic
byte-store self cost changes67,630,327→67,627,453 Ir, while total Ir increases818.
Initialization's dominant generic byte-store self count is exactly unchanged at
116,560,134 Ir. Short-sieve native activity/code footprint is identical. Consequently
its timing movement cannot establish a benefit from store lowering. The small,
inconsistent application changes do not justify retaining this admission rule.
Simulated miss changes are not evidence of hardware behavior or a cache effect.

Report SHA256: applications
`83f88b381bb2613820e7a70bdcccd41737c744520c65d3cc5142b80bfd3990e4`;
native `82283cb7a9eebb6359011140450b57ba9bf42ac3f52fe305188e1c0302d564a7`;
profiles `142fbaff537de1811158443bdbc1b63c1953e312fa9b519a748dbcc6c0c05150`.
Ignored evidence: `build/pvm-arm-byte-store/first/tests`.

## Mixed-span trial: reject the frame-resident store descriptors

The next trial admits exactly one byte store with pure arithmetic before and/or
after it, total4..64 operations in the same already-reserved source block. No later
read/store/host/branch/fault can be speculated: every guard precedes the sole byte
write, and the suffix contains only non-exiting arithmetic. Partial reservations
still use original handlers. This uses the validated guard machinery but replaces
the failed minimum-three-prefix selection rule; it is not an accepted optimization
until its own complete-state paired evidence qualifies. If it also fails, restore
the entire runtime delta from the accepted parent while retaining useful semantic
controls and both measured verdicts. No timing claim for the superseding trial yet.

The mixed-span matrix expands direct native checks to13,520 across all four store
positions, and source/gas/host/remap checks to43,904 per witness build. A separate
320-case later-store matrix proves that a subsequent checked fault retains the
earlier native store's bytes and prefix/suffix registers. The cold builder rejects
late memory guards or a second store; pure arithmetic is the only allowed suffix.
Native compilation, execution and timing remain CI-only.


[Run40766629519](https://github.com/jacogr/ragnarok/actions/runs/40766629519)
measured `c7a516dfde66f5d53da20076136989bfbaa7b860` against
`203cce5615a51aa2f8656d925b4e2be9c3ecb233`, Linux ARM64 with the same pinned
October28 compiler. Independent audits passed all nine native gates/two policies,
13,520 direct literals,43,904 source/gas/host/remap controls and320 later-store exits;
70 processes/910 checked calls/115 controls/16 fresh builds/eight equal-image pairs;
six calibrated cold/reused profiles/78 calls/eight diagnostic builds/four equal-image
pairs/four collection controls. Complete source, compiler, image and reference states
and ordered host events agree. No hardware counters were collected.

CPU milliseconds forward/reverse, reused medians samples1..12. The reference column
is call-only; constructors and cold calls remain separate.

| Workload | Accepted reused | Mixed reused | PolkaVM interpreted call |
| --- | ---: | ---: | ---: |
| Sieve100k | 2.948/2.999 | 2.924/2.958 | 6.084/6.073 |
| Minimal100k | 5.938/5.990 | 6.303/6.309 | 5.511/5.552 |
| Memory fill100k | 4.450/4.550 | 4.523/4.590 | 3.732/3.742 |
| Pinky | 86.999/86.887 | 88.018/88.435 | 87.684/87.535 |
| Sieve10m | 282.944/284.261 | 283.281/283.300 | 332.053/338.461 |
| DOOM initialization | 325.844/320.153 | 330.856/333.678 | 624.034/627.887 |
| DOOM gameplay | 46.509/46.379 | 46.021/45.786 | 40.046/40.080 |

| Workload | Accepted constructor | Mixed constructor | Accepted cold | Mixed cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.889/2.862 | 3.009/2.876 | 10.421/10.461 | 10.588/10.525 |
| Minimal100k | 0.016/0.015 | 0.014/0.018 | 6.145/6.233 | 6.572/6.543 |
| Memory fill100k | 0.054/0.056 | 0.055/0.056 | 8.519/8.723 | 8.493/8.229 |
| Pinky | 0.724/0.728 | 0.747/0.706 | 91.378/90.890 | 92.231/92.741 |
| Sieve10m | 2.984/3.011 | 3.002/3.033 | 292.285/291.486 | 290.944/291.119 |
| DOOM initialization | 8.576/8.552 | 8.575/8.679 | 352.654/341.598 | 353.158/359.563 |
| DOOM gameplay | 8.533/8.507 | 8.639/8.583 | 63.525/64.730 | 63.803/63.485 |

Gameplay improves about1.1/1.3%, but minimal regresses6.2/5.3% and initialization
1.5/4.2%. This fails the retention gate. Minimal native activity and code footprint
are exactly unchanged; a cause cannot be inferred from instruction counts alone.
Gameplay native operations increase93,369,909→106,688,713 while branch calls fall
20,525,709→7,212,349: mixed spans leave more terminal branches checked. This is a
bounded next boundary to examine, not evidence that branch fusion will improve CPU.
Reused gameplay Ir falls616,325,358→608,131,339; initialization falls only
3,238,314,250→3,238,256,397. Simulated conditional/indirect misses are
1,565,075/8,523,586→859,904/8,266,334 for gameplay and
2,162,754/23,899,878→1,192,595/23,823,095 for initialization. These are simulated
counts, not measured hardware behavior. The same fixed cache ceilings remain.

Report SHA256: applications
`7150ae8fbe77c29d07b5e216682942ecdef7da356948c9859c784d83d8e394c1`;
native `a2813592f1836de5a15669ad2a74b9967b87ef8271f30b5c6a0f6812a4805910`;
profiles `1abe7a53a82a9accfad1ab8541b7b132c6430152409b80f2a929d9cf547d9789`.
Ignored evidence: `build/pvm-arm-byte-store/mixed/tests`.

## Call-local context alternative (pending)

Keep exactly the mixed admission and every semantic guard, but remove the additional
72-byte store descriptor array from FlatFrame. A private24-byte context borrows the
existing read descriptors and a fixed dirty-bitmap view only for callArmStore;
code and frames never own it. A positive read extent reconstructs its full byte
length by adding seven; an empty extent refuses before pointer extraction. Caller-
saved D1 preserves the call context while D0 holds the admitted byte pointer.
Distinct cold builder modes prevent read-window and byte-store context confusion.
The direct literal matrix includes both writable roles and an empty bitmap view.
This tests whether restoring the original frame footprint helps; the previous
regression's CPU cause remains unproven. Require fresh complete-state/native and
paired timing/profile qualification against the accepted non-store parent. If this
also fails, remove the runtime store delta and retain useful checks and evidence.
