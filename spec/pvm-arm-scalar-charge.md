# Scalar ARM region source-charge matching

## Scope and invariant

Independent draft layer in stack1786. The accepted region wrapper spends substantial
measured work on metadata/context boundaries. This isolated trial matches original
header/price/span values directly against each cached scalar record while gathering
the same guarded-return header list. It removes temporary span/price arrays and their
second comparison loop; it does not hoist checks across calls or assume immutable prices.

Every active and inactive record remains checked, including the two-block region's
third sentinel/zero lane. Header bounds, source-owner leases, pricing mode, paid state,
barrier, root identity, gas/source ordering, checked memory, publication and native
emission/accounting are unchanged. All source header reads still happen before a
mismatch selects the original fallback. No capacity, admission or hotness change.
The original complete-array matcher remains as the independent test oracle.

## Qualification and decision

The native witness adds111 checks for unpublished owners and genuine two/three-block
records, both rotations and all exercised price widths. Each header/span/price field,
including inactive sentinels, is independently changed and must agree with the old
complete matcher. Existing full register/gas/source-prefix/paid-state/host/memory
checks and native/refused ownership controls remain.

All native builds/execution/timing stay on CI. Keep only qualified useful same-runner
paired benefit without material regressions, otherwise restore only the runtime
helper/wrapper delta while retaining useful tests and measured rejection evidence.
Constructor/cold/reused public calls, retained-frame lifecycle and reference restoration
remain separate. Paired ARM explicit-marker profiles retain exact source/image/native
activity, thirteen checked calls and all calibration controls. Qualified verdict below; measured-head provenance is retained after stack reconciliation.

The first native attempt40752812240 stopped before execution: a `range[2..3]`
iterator start caused the pinned iterator to form an invalid narrow value1.
The inactive-record loop now explicitly widens its cursor to `int`; the checked
`range[0..2]` record conversion remains. This is not a passing runtime or timing
receipt, and no checks/deadlines are weakened. A fresh exact-head run is required.


## Qualified verdict: retain the bounded source matcher

[Run40753700833](https://github.com/jacogr/ragnarok/actions/runs/40753700833)
measured candidate `753cde6da2379612f3100769feb5745a483bc157` against parent
`426d97c5e7f8e3475271517f5a0fb37b3cf04e14` on one Linux ARM64 runner
(reported CPU identity `aarch64`; no particular CPU model is inferred).
Both use October28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`.
Later native restacking restores a rejected x86-only emitter in the lower layer;
ARM sources are unchanged. These measurements belong to the original exact heads.

All nine native gates/two policies passed, including111 scalar/full-matcher
mutation cases, source budgets, gas/paid state, complete memory and ownership
controls. The cohort passed70 processes/910 calls,115 positive/refusal controls,
16 fresh builds/eight equal-image pairs, complete CPU/register/gas/page/permission/
source snapshots and ordered host events. Six explicit-marker cold/reused profiles
passed78 checked calls, four calibration controls, eight diagnostic builds/four
equal-image pairs and exact source/helper/input/compiler/image seals.

CPU milliseconds forward/reverse order. Reused is the median of samples1..12;
constructors and cold sample0 remain separate. Reference calls exclude restoration
and teardown, and are not treated as the same lifecycle as our immutable publication.

| Workload | Parent reused | Scalar reused | PolkaVM interpreted call | Scalar/parent |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.979/3.016 | 2.927/2.987 | 6.055/6.086 | 0.983/0.991 |
| Minimal100k | 6.004/6.175 | 6.174/5.929 | 5.540/5.522 | 1.028/0.960 |
| Memory fill100k | 4.409/4.373 | 4.415/4.378 | 3.739/3.747 | 1.001/1.001 |
| Pinky | 86.935/86.803 | 87.913/86.740 | 87.509/87.416 | 1.011/0.999 |
| Sieve10m | 289.224/288.945 | 283.118/283.273 | 336.609/335.307 | 0.979/0.980 |
| DOOM initialization | 311.613/320.548 | 321.866/316.930 | 628.577/629.034 | 1.033/0.989 |
| DOOM gameplay | 45.952/46.293 | 45.654/45.799 | 40.040/40.015 | 0.993/0.989 |

| Workload | Parent constructor | Scalar constructor | Parent cold | Scalar cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.934/2.886 | 2.976/2.803 | 10.543/10.529 | 10.624/10.406 |
| Minimal100k | 0.015/0.014 | 0.017/0.015 | 6.226/6.217 | 6.205/6.131 |
| Memory fill100k | 0.055/0.054 | 0.055/0.055 | 8.473/8.125 | 8.307/8.050 |
| Pinky | 0.738/0.727 | 0.711/0.708 | 90.927/90.857 | 91.418/90.831 |
| Sieve10m | 3.046/3.011 | 3.083/3.032 | 297.652/296.066 | 292.622/291.432 |
| DOOM initialization | 8.430/8.497 | 8.490/8.450 | 336.860/343.693 | 344.752/339.861 |
| DOOM gameplay | 8.449/8.513 | 8.427/8.555 | 64.168/64.663 | 63.202/64.071 |

| Scope | Parent Ir | Scalar Ir | Parent conditional/indirect simulated misses | Scalar conditional/indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve cold | 114,324,072 | 113,774,095 | 852,837/429,285 | 1,059,320/429,279 |
| sieve reused | 47,188,419 | 46,638,431 | 107,508/395,199 | 215,948/395,198 |
| init cold | 3,341,323,730 | 3,341,188,250 | 2,487,760/23,994,006 | 3,580,301/23,991,123 |
| init reused | 3,238,449,730 | 3,238,314,250 | 1,061,859/23,901,428 | 2,162,754/23,899,878 |
| tick cold | 645,069,336 | 645,069,336 | 878,430/8,548,986 | 1,963,973/8,549,435 |
| tick reused | 616,325,358 | 616,325,358 | 476,877/8,522,942 | 1,565,075/8,523,586 |

Long sieve improves2.11%/1.96%, with short sieve1.75%/0.96% faster in both
orders. Reused short sieve removes549,988 instructions (1.17%) and199,997
conditional branches while preserving native calls/operations. This is a modest
sieve-specific benefit from removing temporary matching work, not an overall
application speed claim. The simpler scalar helper is retained on that evidence.
Memory fill is effectively unchanged; Pinky/minimal/init change inconsistently
with process order and have no established gain or material consistent regression.
Gameplay's small reduction is below useful confidence and its reused Ir is exactly
unchanged. In particular the initialization forward/reverse spread prevents calling
either its slowdown or improvement established.

Simulated conditional misses increase substantially, including gameplay where Ir
and conditional-branch counts are unchanged. They do not establish a hardware
cause or a cache effect. No hardware counters/cache simulation were collected.
No larger cache, skipped source check or changed admission policy is retained.
Profiles match each role's measured native activity and generated source/image
hashes; intermediate dump seals cover all thirteen executions, with cold/reused
raw profiles retained. Retained-core reset/publication and reference restoration/
teardown remain separately available in the full cohort, not folded into this table.

Applications report SHA256
`778bee924504eff7f21d51b6bea48da468df77f1d5d4684f408607cfca5bd55c`;
native `c9f9ad6ff1dc01695f98eb7b63ffdfd46d590b41e4d0d9a8a52c542b07652251`;
profiles `492f0d24d6b9e8035762176a8651ef36e64c64463566a1fd3b9895bf7abc5028`.
All14 baseline/current native activity/code-footprint pairs and kernel cache
receipts are identical, independently checked across both process orders.
Ignored downloaded evidence: `build/pvm-arm-scalar/first/tests`.
Next bounded direction: measure guarded pure-prefix/byte-store lowering; the generic
byte-store worker remains a substantial gameplay profile cost. No store lowering
is part of this layer.
