# Compact x86 immediate operands

## Bounded trial

This isolated layer removes scratch constant loads for full64 wrapping ADD/AND/OR/XOR
and immediate comparisons only when signed8 or signed32 extension reproduces every
original constant bit. Other bit patterns retain the original MOVabs form. Guest
register aliases, checked register storage, all source/gas/quota/PC/exit conventions,
branch selector tails, native admission and ownership remain unchanged. No optional
CPU instruction set, new memory guest opcode or ARM runtime change is introduced.

Independent native literals cover16 complete64 constants around both signed width
boundaries, nine source values, distinct/self/high-register arithmetic aliases and
all ten immediate comparison predicates:3,168 complete-register/return checks.
Existing source prefixes, regions, host boundaries, refused builds and actual owner
lowering controls remain. All native work is CI-only with pinned October28 Nimony.

## Decision gate

Keep/reject depends on exact-head full-state paired measurements and calibrated
profiles. Keep only useful same-runner benefit without material regressions. If
rejected, restore only this emitter delta and retain useful literals and evidence.
Separate constructors/cold/reused/core and reference lifecycle, both process orders;
never interpret simulated branch misses as hardware measurements.

The first CI attempt40756924671 stopped during semantic compilation before native
execution: `compactWidth` returned an unconstrained int, so the caller could not
prove the narrowing to1..4. The helper now declares its actual0..4 result range;
the existing nonzero guards preserve the lower bound. No assertion, range or
bounds check was disabled. The failed receipt is retained locally.


## Qualified verdict: reject runtime, retain boundary witnesses

[Run40757588772](https://github.com/jacogr/ragnarok/actions/runs/40757588772)
measured candidate `de18ef7ed71e24f3883399cf4bcb711cace1d38f` against
`ad50ce72c9c810cea20e43b5c1366def9560db96` on one AMD EPYC9V45 runner,
pinned October28 Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`.
Later documentation/native restacking does not change that measured provenance.
The isolated runtime emitter delta is restored exactly from the accepted parent;
3,168 independent native boundary/alias cases and their strict receipt remain.

All15 native gates passed, including the actual published owner move/copy controls.
The cohort passed70 processes/910 complete-state checked calls,115 positive/refusal
controls,16 private compiler-cache builds/eight equal-image pairs, all source/input/
compiler/image seals and ordered host events. Independent downloaded-receipt audits
verify748 tracked identities, six calibrated profiles/78 checked calls and four
scope controls. Profiling clocks are discarded; no hardware counters or cache
simulation were collected. Simulated misses below are not hardware measurements.

CPU milliseconds forward/reverse order; reused is the median of samples1..12.
Reference calls exclude restoration and teardown; constructors/cold/core/reset/
immutable publication retain their distinct scopes in the complete cohort.

| Workload | Parent reused | Compact reused | PolkaVM interpreted call | Compact/parent |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 1.720/1.743 | 1.716/1.711 | 3.751/3.824 | 0.998/0.982 |
| Minimal100k | 3.483/3.471 | 3.511/3.437 | 3.841/3.751 | 1.008/0.990 |
| Memory fill100k | 2.516/2.712 | 2.624/2.665 | 2.626/2.541 | 1.043/0.983 |
| Pinky | 62.718/64.466 | 63.124/63.370 | 90.209/89.278 | 1.006/0.983 |
| Sieve10m | 163.267/167.716 | 165.849/165.194 | 261.719/265.045 | 1.016/0.985 |
| DOOM initialization | 280.828/293.857 | 285.592/294.454 | 422.146/440.465 | 1.017/1.002 |
| DOOM gameplay | 29.397/30.730 | 32.504/32.719 | 33.131/33.170 | 1.106/1.065 |

| Workload | Parent constructor | Compact constructor | Parent cold | Compact cold |
| --- | ---: | ---: | ---: | ---: |
| Sieve100k | 2.448/2.372 | 2.566/4.014 | 8.246/8.240 | 7.972/7.723 |
| Minimal100k | 0.019/0.016 | 0.018/0.020 | 3.665/3.555 | 3.662/3.539 |
| Memory fill100k | 0.051/0.054 | 0.053/0.053 | 7.971/8.027 | 6.774/8.046 |
| Pinky | 0.544/0.579 | 0.572/0.559 | 66.993/68.787 | 67.301/65.370 |
| Sieve10m | 2.660/2.660 | 2.788/2.677 | 172.718/165.640 | 173.160/169.826 |
| DOOM initialization | 6.583/9.648 | 6.707/6.967 | 315.441/325.892 | 321.492/324.783 |
| DOOM gameplay | 8.796/6.736 | 6.591/6.701 | 52.243/49.997 | 51.945/53.281 |

| Scope | Parent Ir | Compact Ir | Parent conditional/indirect simulated misses | Compact conditional/indirect simulated misses |
| --- | ---: | ---: | ---: | ---: |
| sieve cold | 114,161,993 | 113,359,925 | 740,224/504,033 | 693,469/503,490 |
| sieve reused | 42,529,378 | 42,127,284 | 62,731/466,285 | 12,735/466,285 |
| pinky cold | 1,112,783,584 | 1,108,761,867 | 2,130,203/21,196,756 | 2,132,379/21,195,743 |
| pinky reused | 1,087,438,641 | 1,083,864,872 | 1,827,773/21,176,047 | 1,827,787/21,176,046 |
| tick cold | 616,018,976 | 615,314,260 | 1,042,690/11,210,280 | 1,043,088/11,209,782 |
| tick reused | 584,515,591 | 584,104,326 | 663,257/11,182,072 | 663,224/11,182,072 |

Reused Ir falls0.95% on short sieve,0.33% on Pinky and0.07% on gameplay.
Gameplay nonetheless slows10.57%/6.47%; sieve/Pinky timings do not establish a
consistent useful gain. This trial is rejected rather than attributing a hardware
cause from instruction counts or simulated misses. A separate ALU-only or
comparison-only policy remains an unproven future possibility, not a retained
runtime option. No replay is needed to reject an optional complexity with these
unhelpful application results.

Each profile matches its role's unprofiled native activity; normal kernel cache
receipts retain the same node/operation occupancy. Generated code is smaller but
that alone is not a user-visible speed benefit. Timing binaries are sealed by the
runner's image hashes, not retained in the artifact. Retained-core and reference
restoration/teardown measurements are not mixed into the public ratios above.

Report SHA256: applications
`dba1b10bfa1a0e6daa466c5286379c09c8cf2adaac5df21088ef2ffa5c65e37a`;
native `f8c9126812b3e037696f891b324947993ba1052588321de34a4be7cccf319a90`;
profiles `2fc56e87c0e2b405227846980e6202aebc7333eaf38948a708a87e5e9df0676e`.
Ignored downloaded evidence: `build/pvm-x86-compact/first/tests`.
