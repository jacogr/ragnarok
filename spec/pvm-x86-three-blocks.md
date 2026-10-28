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
