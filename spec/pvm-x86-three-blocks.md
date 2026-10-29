# Bounded x86 three-block investigation

## Scope and profile preparation

The ARM interpreter's native path can connect the existing exact three-shape pure
closed round. The x86 path currently admits at most two connected blocks. This is
a logical coverage difference worth investigating; it does not establish a CPU
cause or permit cross-machine timing ratios.

This layer currently adds an explicit x86 initialization profile alongside the
existing sieve/Pinky/gameplay scopes: eight calibrated baseline/current profiles,
104 complete checked calls, the same thirteen calls per scope and the same normal
source/input/compiler/image seals. Direct callers retain the original three-scope
plan unless `--include-init` is supplied; the manual native x86 profiling Make
target explicitly requests it. ARM's existing initialization plan is unchanged.
A durable selected case/limit manifest accompanies the profile role manifest.
The native CI-only refusal is tested without launching any compiler or guest.

The resident-register trial was rejected after its bounded exact-head replay; none
of that runtime/cache-selection implementation is retained. This trial admits the
existing exact three-shape round only after a complete positively checked closed
round. One source-owned region, unchanged physical1MiB code arena,1024 total
publications and262144 metadata coordinates remain. Ordinary publications stop at
1023, reserving one existing slot for the region rather than increasing capacity.
The private record grows72→88bytes for its third scalar proof; the invocation-only
context becomes six words (gas/quota/three visits/last completed header). The opaque
C trampoline and public API are unchanged. Every active/inactive field is matched;
all three genuine original header workers are retained for paid/pricing/partial
and guard fallback, including rotations of the exact source shape.

The native witness retains1,440 original one/two-block contexts and adds720 exact
three-block contexts,3,546 independent canonical single-step source/gas/pricing/
rotation/exit/cache-transfer cases, and physical publication-reservation evidence.
The generic whole-region2,120-opcode arithmetic matrix and all prior native/refusal/
host/memory/ownership/literal controls remain. No cache-count lookup policy, async
gas or relaxed memory semantics is introduced. All native work is CI-only; no speed
claim before complete-state same-runner paired timing and eight calibrated profiles.
If unhelpful, restore only this runtime delta, retaining meaningful tests/evidence.

The first CI attempt40772401188 stopped during witness semantic compilation:
a top-level `registers` value resolved as the imported module in the new capacity
block. Renamed it `capacityRegisters`; no runtime assertion, bounds guard or source
case was removed. Originating logs are retained under ignored build/. A fresh
exact-head native/timing/profile run is required.

Attempt40773957482 exposed the same top-level `when` scope issue for two other
capacity locals. The complete capacity check now lives in a procedure with explicit
slot arguments, eliminating module-level local collisions as a class. All controls
remain; neither compile failure is a passing native receipt.

Native attempt40774762322 passed all original/literal/raw-context matrices before
the new source-shape warm assertion failed. Inspection identifies a missing
allocation path: these exact short shapes intentionally admit no ordinary leaf,
while the old region publisher required an existing arena. Region publication now
uses the same lazy exclusive arena allocation/sticky refusal contract as ordinary
publication, preserving the explicit refusal define. The raw three-block contexts
also start with zero ordinary fragments to prove this prerequisite independently.
Focused state/warm diagnostics remain; no source or native assertion is weakened.

## First three-block admission verdict: reject without promotion

[Run40776015811](https://github.com/jacogr/ragnarok/actions/runs/40776015811)
measured `b8733d2758f1e9f23d9000ea1400502ee13f3b23` against
`07895cad346b28dce99f6c268169aaa589c4c055`, AMD EPYC9V45 with pinned October28
Nimony63fed6cb4b2f59d34c9fbb18f1796e671e2024e4. All fifteen native gates,
1,440 original contexts,720 three-block contexts,2,120 arithmetic contexts,
3,168 literal cases,3,546 source controls and the genuine capacity witness passed.
Independent artifact audits passed70 processes/910 checked calls/115 controls,
16 private fresh builds/eight equal-image pairs, source/compiler/image hashes,
complete reference state/snapshots/host events, eight cold/reused profiles with
104 checked calls and four collection controls. No hardware counters were collected.

CPU milliseconds forward/reverse, reused medians samples1..12; reference call-only.
The checked interpreter is from the same source/image with explicit interpreted
selection, not a different master runner. Constructors and cold calls are separate.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 1.742/1.775 | 1.835/1.946 | 2.085/2.123 | 3.956/3.913 | 0.464/0.497 |
| Minimal100k | 3.442/3.564 | 3.557/3.581 | 3.487/3.586 | 4.418/3.994 | 0.805/0.897 |
| Memory fill100k | 2.388/2.443 | 2.401/2.569 | 2.490/2.500 | 2.618/2.681 | 0.917/0.958 |
| Pinky | 65.818/66.205 | 64.279/65.882 | 78.870/78.675 | 91.623/93.404 | 0.702/0.705 |
| Sieve10m | 171.341/171.515 | 174.654/176.056 | 207.195/209.520 | 263.927/269.333 | 0.662/0.654 |
| DOOM initialization | 285.005/281.454 | 300.107/290.191 | 296.099/285.334 | 453.249/445.496 | 0.662/0.651 |
| DOOM gameplay | 30.744/29.423 | 33.123/29.237 | 32.042/31.040 | 34.731/32.194 | 0.954/0.908 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.693/2.621 | 2.494/2.481 | 7.741/7.975 | 8.519/8.570 |
| Minimal100k | 0.016/0.018 | 0.016/0.021 | 3.540/3.747 | 3.697/3.765 |
| Memory fill100k | 0.049/0.051 | 0.060/0.049 | 8.000/8.029 | 8.333/6.920 |
| Pinky | 0.593/0.586 | 0.586/0.587 | 70.175/69.520 | 67.489/69.468 |
| Sieve10m | 2.541/2.510 | 2.780/2.632 | 178.313/176.471 | 176.236/178.739 |
| DOOM initialization | 6.867/6.641 | 6.725/9.092 | 318.676/313.344 | 329.028/325.327 |
| DOOM gameplay | 6.976/6.460 | 6.796/6.309 | 54.905/49.910 | 54.380/49.779 |


Long sieve regresses1.9/2.6%, short sieve5.3/9.6%, initialization5.3/3.1%.
Gameplay7.7%slower/0.6%faster is inconsistent; Pinky2.3/0.5%better cannot rescue
these regressions. Native activity/code bytes are identical on sieve, Pinky and
gameplay: the added capability does not reach their execution. Initialization
loses one ordinary publication (1,024→1,023), with62,653,474→62,476,570 native
operations and94,821→94,702 code bytes under the same1MiB physical ceiling.
This variant fails the retention gate and is superseded by the bounded policy
trial below; it is not an accepted speedup.

Reused sieve Ir42,529,290→43,779,768 includes region adapter self
6,250,000→7,100,000 and native-call accounting5,050,000→5,250,000. Larger scalar
bookkeeping adds work even when the third block is unused. Initialization total
Ir6,784,519,887→6,875,511,020; the dominant checked charged-shape self row is
4,056,317,884→4,139,214,917. Raw call arcs prove only one connected-region call
in the entire measured initialization invocation, while that hot shape remains
checked. A smaller earlier region occupies the sole cache; this is an admission
opportunity, not proof that native promotion will improve CPU time. The ordinary
cache ceiling/payload and code working set must remain part of the comparison.

| Reused scope | Previous conditional/indirect simulated misses | Trial conditional/indirect simulated misses |
| --- | ---: | ---: |
| Sieve | 62,771/466,285 | 126,082/466,285 |
| Pinky | 1,827,793/21,176,047 | 1,615,968/21,176,046 |
| DOOM initialization | 1,737,428/23,212,582 | 1,785,549/23,222,375 |
| DOOM gameplay | 663,873/11,182,072 | 703,038/11,182,072 |

Simulated misses are not hardware measurements or a CPU-cause explanation.
Report SHA256: applications
`7910c76b1d82955c64a511cb044d937cffc5c248b4d97142340743797888701c`;
native `c107ec7d13616cf5f82b12be093fb786f2332b4f2ceba6536ca5a26afc6df2c9`;
profiles `c956043d16b5225292a1fb9bdd3928c6cf0d00082e0a77ed33fdf06d941f709f`.
Ignored exact evidence: `build/pvm-x86-three/qualified/tests`.

## Bounded one-time promotion trial (pending)

Permit one strictly larger three-block proof to supersede an existing one/two-block
region after a genuine complete checked round. The private cache remains one88-byte
record; the six-word invocation payload and direct coordinate metadata are unchanged.
There is no associative lookup, extra cache, hotness counter or new frame field.
Publication uses the same append-only1MiB arena and1,024 total ceiling. Preserve a
cold scalar snapshot of the previous tag/counters while attempting publication;
any shape/code/capacity refusal restores it exactly. Only successful publication
restores the old root's genuine original worker and installs the new root. Prior
connected call/block statistics remain cumulative. A three-block cache cannot be
replaced again, so promotion and retired code are bounded once per stream owner.
No native call/host callback is active during this exclusive cold transition.

Direct controls prove malformed-publication rollback, successful replacement and
retained visit statistics; a full publication budget proves failed promotion leaves
the earlier native proof callable. Each source rotation now first claims the cache
with a short unrelated loop, executes the triple, then returns to the old loop.
All original budgets/gas/pricing/transfer/source checks remain, plus six complete-
state cold-to-hot/old-root controls. Require the full fresh paired cohort and eight
profiles against the accepted pre-trial parent. If useful real coverage and CPU
gain do not qualify without material regressions, restore this entire runtime
extension while retaining meaningful evidence, profile support and semantic checks.

## Promotion qualification: useful initialization gain, bounded replay pending

[Run40780678777](https://github.com/jacogr/ragnarok/actions/runs/40780678777)
measured `83c28ccb94ea7e42a984a5cbedabb8a88f30424a` against the same accepted
`07895cad346b28dce99f6c268169aaa589c4c055`, now on AMD EPYC7763. Never combine
its raw timings with the preceding9V45 runner. Independent audits again pass all
70 processes/910 calls/115 controls/16 fresh builds/eight equal-image pairs,
fifteen native gates, all original matrices and the added promotion/rollback/
full-capacity/old-root controls, plus eight calibrated profiles/104 checked calls
and four collection controls. Source/compiler/image/reference-state/host-event
and snapshot checks all agree. No hardware counters were collected.

CPU milliseconds forward/reverse; reused samples1..12. Reference is call-only.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 3.260/3.276 | 3.289/3.306 | 3.935/3.908 | 6.035/6.064 | 0.545/0.545 |
| Minimal100k | 6.331/6.345 | 6.326/6.480 | 6.362/6.408 | 7.472/7.472 | 0.847/0.867 |
| Memory fill100k | 4.460/4.470 | 4.439/4.438 | 4.736/4.559 | 4.184/4.205 | 1.061/1.055 |
| Pinky | 132.650/131.499 | 127.512/128.206 | 161.466/161.257 | 190.569/186.448 | 0.669/0.688 |
| Sieve10m | 322.881/325.534 | 325.255/330.417 | 383.146/372.365 | 444.010/443.087 | 0.733/0.746 |
| DOOM initialization | 583.759/567.970 | 327.133/320.256 | 624.412/597.351 | 775.132/776.177 | 0.422/0.413 |
| DOOM gameplay | 56.031/56.714 | 58.318/56.212 | 57.955/59.694 | 52.359/52.675 | 1.114/1.067 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 3.879/3.678 | 3.973/3.682 | 11.913/12.525 | 12.626/12.998 |
| Minimal100k | 0.019/0.018 | 0.017/0.018 | 6.716/6.627 | 6.582/6.894 |
| Memory fill100k | 0.064/0.064 | 0.064/0.064 | 11.697/11.574 | 11.725/11.868 |
| Pinky | 0.857/0.823 | 0.822/0.876 | 143.703/138.794 | 136.370/135.542 |
| Sieve10m | 3.762/3.707 | 4.149/3.790 | 331.583/335.269 | 329.583/339.741 |
| DOOM initialization | 10.992/11.206 | 11.114/10.984 | 624.535/607.239 | 368.124/368.612 |
| DOOM gameplay | 14.211/10.846 | 11.148/11.260 | 90.701/83.522 | 82.075/87.309 |


Initialization improves44.0/43.6%, including cold calls624.535/607.239→368.124/368.612ms.
The targeted region now reaches real work: native operations62,653,474→2,277,407,810,
with only94,821→95,042 code bytes and1,024→1,023 publications under the unchanged
physical ceiling. Reused initialization Ir6,784,519,887→3,957,044,643; its dominant
checked-shape self row4,056,317,884→867,834. This is concrete reduction of checked
shape work, not an inference from simulated misses. Constructors remain separate.

Other source activity is unchanged. Long sieve is0.7/1.5%slower; minimal is nearly
unchanged/2.1%slower; Pinky3.9/2.5%faster. Gameplay4.1%slower/0.9%faster is inconsistent.
A bounded fresh-process replay will check these smaller tradeoffs before final
retention. It retains the three original replay workloads and adds gameplay and
long sieve: sixty fresh baseline/current processes, six per role/case,780 extra
complete checked calls, both relative role orders. Normal70-process/910-call
qualification and115 controls remain mandatory. Gameplay uses its own ordered
host-event fixture, not initialization's. Timings from different CPU models stay
separate; replay warm medians use samples3..12 and cannot silently replace the
ordinary reused scope. No further runtime optimization is mixed into this replay.

| Reused scope | Previous conditional/indirect simulated misses | Promotion conditional/indirect simulated misses |
| --- | ---: | ---: |
| Sieve | 62,771/466,285 | 12,746/466,286 |
| Pinky | 1,827,793/21,176,047 | 1,240,415/21,204,165 |
| DOOM initialization | 1,737,428/23,212,582 | 1,719,072/23,234,922 |
| DOOM gameplay | 663,873/11,182,072 | 523,025/11,182,072 |

These simulated misses are not hardware measurements. Applications SHA256
`371c69ec9789df233ad5313aa2605e752f2ee02a45769851f1471aeae957035f`;
native `847db5fd1d71f015b3f3b72e76c702f0c423e0d9c5a25c6b16bc6f5867bdd60c`;
profiles `6d8c5cf4ff09e82f77935df2ab1cc998c42a9117aef0eff529223b06e7750baa`.
Ignored evidence: `build/pvm-x86-three/promotion/tests`.

## Replay verdict and compact-proof correction (pending)

[Run40788548505](https://github.com/jacogr/ragnarok/actions/runs/40788548505)
measured `80c57289185c0302ec9f8c21d65e9b037ecae998` on AMD EPYC7763. Independent
checks passed the normal70 processes/910 calls/115 controls/16 builds/eight equal
pairs and fifteen native gates, plus all sixty replay processes/780 calls. Total:
130 processes and1,690 complete-state checked calls. Raw logs, thirteen-call
framing, host events and native activity agree; baseline/current kernel/DOOM images
are byte-identical to the preceding promotion run. No new runtime was introduced.

CPU milliseconds across six process medians per role/case, warm samples3..12;
minimum/maximum are process medians, not individual call extrema.

| Workload | Previous median (min..max) | Promotion median (min..max) |
| --- | ---: | ---: |
| DOOM initialization | 585.392 (565.286..697.398) | 328.150 (324.018..330.321) |
| Minimal100k | 6.337 (6.327..6.422) | 6.328 (6.309..7.246) |
| Pinky | 131.692 (128.874..132.365) | 127.891 (127.220..130.483) |
| DOOM gameplay | 56.986 (55.641..58.747) | 59.223 (58.271..59.882) |
| Sieve10m | 326.554 (324.350..341.543) | 328.151 (322.086..341.970) |

Initialization's43.9%gain repeats, but gameplay's3.9%regression also repeats and
must be addressed before a final keep verdict. Native gameplay work/code footprint
is unchanged, so simulated counts do not establish the cause. The88-byte proof
record enlarges the hot owner and changes entries/counter offsets; that is a
bounded representation issue to test, not a proven hardware explanation.

The correction retains the checked publication invariant operations==span, stores
each already bounded2..65 span in one byte, and derives logical operation counters
from the existing validated attempt product. Headers/code/count stay32-bit, prices
and visit counters stay64-bit. The private proof is64 bytes, smaller than the old
72-byte two-block record. All active/inactive header/span/price matches remain,
including full-width caller arguments and high-bit price mismatches. No source,
gas/quota, ABI, capacity or native instruction stream changes. A local cold assert
precedes narrowing; invalid input still refuses before publication. Add exact tag
mismatch and65-span/invalid-span controls. Compare the whole corrected model to
the accepted pre-trial parent with all seven workloads and eight profiles; retain
only useful benefit without material regressions. The paired-shift child remains
an independent arithmetic trial and is not included in this correction's receipt.

Replay applications SHA256
`c7e5731c804e8fafc13c50659aac6a5e28264b1ef6c217457214728337fbf712`;
native `6dd1fe8e62ad5d6bbd71718f4d4366826a9cf3e0d227d6be90e752175f64ea54`.
Ignored evidence: `build/pvm-x86-three/replay/tests`.

## Compact64-byte model verdict: reject

[Run40794754598](https://github.com/jacogr/ragnarok/actions/runs/40794754598)
measured `fb3d0b13f2c24bd3be456dab05f51bfb362953d1` against accepted
`07895cad346b28dce99f6c268169aaa589c4c055`, AMD EPYC9V45, same pinned
October28 compiler. All15 native gates,52 full-width active/inactive tag controls,
5 maximum/invalid-span controls and prior matrices passed. Independent audits
passed70 processes/910 calls/115 controls/16 fresh builds/eight equal-image pairs,
full state/source/host events and eight cold/reused profiles/104 calls/four controls.
No hardware counters were collected. The paired-shift child is excluded.

| Workload | Previous JIT | Trial JIT | Checked interpreter | PolkaVM interpreted call | Trial/reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve100k | 1.566/1.610 | 1.620/1.657 | 1.927/1.930 | 3.567/3.648 | 0.454/0.454 |
| Minimal100k | 3.306/3.269 | 3.282/3.313 | 3.363/3.316 | 3.638/3.633 | 0.902/0.912 |
| Memory fill100k | 2.238/2.205 | 2.179/2.151 | 2.275/2.304 | 2.446/2.425 | 0.891/0.887 |
| Pinky | 60.556/60.369 | 59.275/59.858 | 80.348/80.881 | 86.294/86.778 | 0.687/0.690 |
| Sieve10m | 159.580/157.107 | 164.454/161.669 | 181.016/181.000 | 245.617/249.073 | 0.670/0.649 |
| DOOM initialization | 268.081/267.670 | 162.300/162.996 | 346.143/276.991 | 416.980/418.010 | 0.389/0.390 |
| DOOM gameplay | 27.628/27.646 | 29.698/29.122 | 29.391/28.818 | 31.528/32.023 | 0.942/0.909 |

| Workload | Previous constructor | Trial constructor | Previous cold | Trial cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.253/2.232 | 2.286/2.233 | 7.608/7.621 | 7.412/7.464 |
| Minimal100k | 0.015/0.016 | 0.015/0.016 | 3.466/3.394 | 3.468/3.411 |
| Memory fill100k | 0.048/0.046 | 0.054/0.054 | 6.314/7.288 | 7.493/7.286 |
| Pinky | 0.551/0.542 | 0.554/0.545 | 64.783/64.042 | 63.620/62.561 |
| Sieve10m | 2.483/2.365 | 2.661/2.311 | 164.430/163.159 | 169.863/166.118 |
| DOOM initialization | 6.459/6.464 | 6.762/6.447 | 295.735/296.766 | 189.349/190.013 |
| DOOM gameplay | 6.508/8.718 | 6.608/6.515 | 48.322/51.861 | 50.176/48.593 |

Initialization improves39.5%/39.1%, but long sieve regresses3.1%/2.9% and
gameplay7.5%/5.3%. This representation fails the retention gate despite its size
reduction. Sieve Ir42,529,402→43,729,854 still includes extra three-lane matching
and adapters, with identical native logical work/code bytes. Gameplay Ir changes
only584,514,400→584,792,880 with identical native work. Neither simulated misses
nor smaller metadata establish a hardware cause. Do not retain the64-byte model.

Report SHA256 (applications, native, profiles):

- `663bffc86713caa31c50d966c00285ab37ea3c3d1a957ae1d76d4fe940dc1d0f`
- `d4a0449d566f3b308bdc478d29b15f4ed4df9a5217f3f4486092009f18d5358d`
- `2e247c191607174ad7a7b4688a89526cb38e820e59b06f3f673fa3d8f3e5cae4`

## Preserve the accepted small path: pending isolated correction

Restore the accepted one/two-block two-lane matcher, source adapter, field offsets
and five-word context; use a separate three-block source worker and six-word call.
Both modes share the same exclusive bounded arena and one proof record. A small
call asserts its mode before native code can access its five-word context. The full
six-word raw witness adapts small mode to that original call; the production small
handler calls the five-word ABI directly.

The private proof remains the original72 bytes: first two headers/spans/prices,
code/count and cumulative statistics keep their original offsets. Original scalar
operation words retain their meaning in small mode. Only count==3 reuses these
redundant words as low/high halves of the full third price, with third header/span
in former padding. Publication already requires operations==span; triple operation
counts therefore use the checked attempt product. All third values are restored
on publication refusal with the complete POD snapshot. Third spans narrow only
after an explicit2..65 proof; full-width caller tags are never truncated. No public
layout, memory/pricing/ownership semantics or physical cache policy changes.

Require all existing state/refusal/owner and52/5 proof controls, independent public
both-order seven-workload comparisons and eight calibrated cold/reused profiles.
Inspect generated small-path code and executed work against the accepted parent,
not only record size. No timing claim before qualification. The rejected larger
and64-byte models remain exact measured history. If this separation cannot preserve
useful gains without material regressions, restore the runtime to the accepted
parent and keep meaningful tests/evidence.

The x86 profile helper also retains the four normal measured kernel/DOOM ELFs
(two roles) under deterministic `*-sealed` names, requiring exact image-hash
identity before collection. Execution still uses the original already timed binary;
there is no diagnostic guest build or runtime instrumentation. These copies permit
independent static disassembly of the accepted small path and field access offsets
after CI completes, rather than guessing a CPU cause from aggregate counts.
