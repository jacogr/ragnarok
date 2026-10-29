# Transactional ARM pure-prefix byte store

## Current verdict and historical scope

All three native-store variants are rejected and the runtime extension is removed.
The retained change contains boundary witnesses, minimal profiling and exact trial
evidence. Descriptions below preserve the historical variant scopes and receipts.

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

## Call-local context alternative (rejected)

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

## Compact context verdict: reject; minimal attribution follows

[Run40777246242](https://github.com/jacogr/ragnarok/actions/runs/40777246242)
measured `b26a79a97b2c707cbf583cf049549467bdd88189` against the same accepted
`203cce5615a51aa2f8656d925b4e2be9c3ecb233`. Independent audits passed70 processes,
910 calls,115 controls,16 fresh builds/eight equal-image pairs, nine native gates/
two policies and six profiles/78 calls/eight diagnostic builds/four equal-image
pairs/four collection controls. All prior direct/source/host/dirty/later-store
checks remain enforced. Generated C proves the read descriptor is passed by
pointer, with one24-byte call-local context and no72-byte descriptor copy.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 2.956/3.006 | 2.959/2.943 | 3.495/3.527 | 6.122/6.077 | 0.483/0.484 |
| Minimal100k | 6.262/6.003 | 6.518/6.533 | 6.273/6.169 | 5.531/5.547 | 1.178/1.178 |
| Memory fill100k | 4.427/4.440 | 4.444/4.447 | 4.391/4.430 | 3.755/3.747 | 1.184/1.187 |
| Pinky | 86.851/87.034 | 87.258/87.067 | 95.873/95.223 | 87.433/87.666 | 0.998/0.993 |
| Sieve10m | 283.279/282.967 | 285.998/289.460 | 346.322/338.730 | 333.800/333.400 | 0.857/0.868 |
| DOOM initialization | 325.169/326.843 | 324.227/321.994 | 529.840/542.435 | 627.800/628.291 | 0.516/0.512 |
| DOOM gameplay | 46.356/45.971 | 45.867/45.730 | 48.958/49.019 | 40.070/40.058 | 1.145/1.142 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.874/3.018 | 2.891/2.841 | 10.527/10.597 | 10.579/10.455 |
| Minimal100k | 0.014/0.015 | 0.014/0.017 | 6.294/6.231 | 6.645/6.587 |
| Memory fill100k | 0.054/0.055 | 0.053/0.064 | 8.505/8.345 | 8.609/8.439 |
| Pinky | 0.705/0.702 | 0.730/0.734 | 90.888/91.211 | 91.610/91.209 |
| Sieve10m | 3.142/2.965 | 3.038/2.980 | 292.151/291.576 | 294.107/297.417 |
| DOOM initialization | 8.542/8.502 | 8.496/8.615 | 352.158/355.252 | 349.825/346.430 |
| DOOM gameplay | 8.563/8.494 | 8.485/8.591 | 65.277/64.276 | 64.091/63.859 |


Minimal still regresses4.1/8.8%; long sieve1.0/2.3%slower, gameplay only1.1/0.5%
better. Restoring the original frame footprint did not resolve minimal. Its native
activity/code footprint remains identical; this does not establish a CPU cause.
Reused gameplay Ir increases616,325,358→622,471,028 despite fewer indirect branches
14,032,396→13,007,940. The call-local wrapper itself accounts62,480,897 self Ir;
context setup/guards are real work, not free from a smaller frame. Initialization
Ir3,238,314,250→3,238,295,932 changes minimally. This variant fails the retention
gate; do not claim a retained speedup. Simulated conditional/indirect misses:
sieve215,948/395,198→157,967/395,198; init2,162,754/23,899,878→1,443,598/23,820,352;
gameplay1,565,075/8,523,586→885,094/8,010,654. No hardware counters were collected.

Applications SHA256 `888a15e3cd1d274a323381a6f0d5af2a45e0f041e00f01f55d5cbbe455af9729`;
native `f6a295dac4e0facdd29d6c592b76f1f3c16d877be7b95fc8eb3b3f7b5d08a210`;
profiles `64944f5171a313cf254399674e7e614e8384a3cce53a6848ae2af7c48d57d37f`.
Ignored evidence: `build/pvm-arm-byte-store/compact/tests`.

The next diagnostic leaves runtime exactly unchanged and explicitly adds minimal
to the ARM profile plan, retaining sieve and both DOOM phases. Default direct plans
remain unchanged; the manual ARM profile target opts in. Eight scoped profiles/
104 checked calls use the same eight diagnostic images/four equal-image pairs and
all four collection controls. This measures the regressed workload before any
further store/branch experiment; profiled clocks remain unusable as CPU timings.

## Final store verdict: remove the runtime extension

[Diagnostic run40782041524](https://github.com/jacogr/ragnarok/actions/runs/40782041524)
measured unchanged runtime at `9fdd2b2fed5090e435f58eabec8b220f2e701e4a` versus
`203cce5615a51aa2f8656d925b4e2be9c3ecb233`. Independent audits pass the normal
70-process/910-call/115-control/16-build/eight-pair cohort, nine native gates/two
policies, eight profiles/104 calls/eight diagnostic builds/four equal-image pairs
and four collection controls. Every reference state, source/image/compiler hash,
source snapshot and ordered host event remains checked.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 2.993/3.004 | 2.916/2.936 | 3.479/3.507 | 6.106/6.383 | 0.478/0.460 |
| Minimal100k | 5.991/5.995 | 6.384/6.312 | 6.266/6.197 | 5.492/5.479 | 1.162/1.152 |
| Memory fill100k | 4.412/4.538 | 4.412/4.588 | 4.513/4.538 | 3.728/3.739 | 1.183/1.227 |
| Pinky | 86.977/87.315 | 86.999/87.310 | 95.554/95.702 | 87.746/87.475 | 0.991/0.998 |
| Sieve10m | 285.057/284.056 | 288.316/287.426 | 344.599/338.374 | 333.650/333.489 | 0.864/0.862 |
| DOOM initialization | 310.987/327.889 | 320.885/320.000 | 525.619/537.278 | 625.188/628.332 | 0.513/0.509 |
| DOOM gameplay | 46.499/46.710 | 46.191/46.313 | 49.658/49.427 | 40.082/40.076 | 1.152/1.156 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.947/2.866 | 2.901/2.838 | 10.546/10.454 | 10.497/10.427 |
| Minimal100k | 0.015/0.015 | 0.018/0.017 | 6.225/6.228 | 6.616/6.569 |
| Memory fill100k | 0.056/0.056 | 0.068/0.057 | 8.733/8.275 | 8.632/8.843 |
| Pinky | 0.735/0.744 | 0.778/0.743 | 91.066/91.360 | 91.291/91.603 |
| Sieve10m | 3.091/2.836 | 3.035/2.844 | 292.731/293.287 | 296.746/295.518 |
| DOOM initialization | 8.543/8.579 | 8.653/8.740 | 335.883/351.111 | 341.930/345.115 |
| DOOM gameplay | 8.667/8.589 | 8.552/8.702 | 64.223/64.471 | 64.057/64.871 |


Minimal has exactly96,243,959 Ir,14,206,713 conditional branches,2,000,161 indirect
branches and1,400,027 simulated indirect misses on both sides. Its dominant self
rows and software native activity are identical. Existing hot-kernel functions
also have identical disassembled instruction sequences after relocation. Their
addresses/alignment differ; without hardware measurements this neither establishes
a CPU cause nor justifies blaming added runtime checks. The new store path is not
used by this workload. It deliberately exercises indirect function calls and
counter/pointer memory traffic, so its boundary mix differs from the long loops.

All three store variants fail the useful-gain/no-material-regression gate. Restore
arm64_jit.nim and handler_stream.nim exactly from the accepted non-store parent;
remove store contexts, builders, lowering and dispatch. Keep the strengthened
complete-memory/source-snapshot oracle,43,904 checked-store/gas/host/remap controls,
and adapt the later-store witness to four genuinely native pure operations between
two checked stores:360 complete-state cases plus positive native-activity evidence.
Remove direct literals and native-mutation assertions that require the rejected
emitter. Optional minimal profiling and the exact measured rejection evidence stay.
This is not a retained native store feature or an accepted speedup.

Applications SHA256 `546cd5992b2edf286c8dbfa0b88e5e88399dca5d3eabbbe02790692d23506912`;
native `3a8a225576bf6815c88bd638acd6c3c991965c3601bda4fdd9bae821a1a9a475`;
profiles `90db66fda27c92de9d06500ed7b9ed7f627f3ec5914b26b3a3d91a9c426ecf63`.
Ignored evidence: `build/pvm-arm-byte-store/minimal-profile/tests`.


Post-removal qualification40790232878 found two witness calls mechanically renamed
to the nonexistent finishArmReadSpan. Restore their accepted armReadInstructions
name; no runtime assertion or test case is removed. The originating compile logs
remain under ignored build/pvm-arm-profile/shift-arm-first.log. Fresh exact-head
native qualification is required before declaring the retained witnesses complete.
