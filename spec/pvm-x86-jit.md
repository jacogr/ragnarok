# Linux x86-64 JIT foundation

Scope: independently lower bounded pure register spans from the existing checked handler stream.
The pinned Gray Paper and established `pvm-registers`, `pvm-execution` and `pvm-handler-stream`
contracts remain authoritative. No dependency, compiler, guest-ISA or protocol pin changes.

This first increment is opt-in through `pvmX86Jit`. Ordinary builds retain the existing ARM64
native backend and interpreted fallback on x86. The target is Linux x86-64 SysV only, using
baseline integer instructions without BMI/AVX or other optional CPU extensions. Unsupported
platforms, unavailable executable storage and unsupported operations use checked execution.

The compiler admits four to sixty-four non-exiting pure operations within one already reserved
source block. Headers, branches, memory, host calls, faults and all partial attempt prefixes
remain canonical interpreter paths. The leaf borrows one register array in RDI; caller-saved
RAX/RCX/RDX/R8 hold temporary values. Every original source is loaded before its destination is
stored, including aliases, signed low-word results, comparison flags, variable shift counts and
mixed-signedness upper multiplication. No invocation pointer is embedded in executable code.

The first conservative emitter loads/stores the register array per source instruction; resident
register allocation, compiled branches, memory operations and connected blocks are future work.
This is a correctness foundation and establishes no performance advantage.

An exclusive exact-source stream owns the code cache. Separate writable/executable aliases have
an unchanged one-MiB physical ceiling; individual leaves are bounded by4096bytes, publications
by1024entries and source coordinates by262144nodes. Publication is append-only and16-byte
aligned. Explicit move/copy lowering controls protect frames and streams; fresh invocations and
host memory replacement retain code-only capabilities with original fallback handlers.

`make check-pvm-x86-jit` is CI-only. The manual `jit-x86` suite uses the existing PVM Comparison
job on native Linux x86-64, preserving incomplete/failure receipts. It requires positive native
arithmetic execution, complete source-prefix agreement, warm-cache reuse, explicit executable
refusal, the existing opcode/memory/host/source-state suites, public policy tests, intended
ownership rejection and OS publication/capacity/retirement controls. All assertions, bounds,
release/ARC and Clang ThinLTO settings remain enabled. Initial exact-head Linux x86-64 qualification passed at
`bc789e550b7637d7ab7bbdf641490feef26bd526` in
[run40663403634](https://github.com/jacogr/ragnarok/actions/runs/40663403634).
Thirteen gates pass, including2,120scalar and2,984source-prefix cases in each native/refused
profile and the existing56,800source-state boundary cases per profile. Independent downloaded
receipt verification matches472source/compiler identities and every raw build/run log;
compiler SHA256:`c31a8e022a831546fff4f918b2fcead217bcc159ec1b02c61b8dcbc70ffe2b19`.
Report SHA256:`b8da02c041e72509a132607a7f3f951ac83001ddd79774e3b98af205ba41d91a`.
Default-source Compile/Smoke also passes. This correctness result is not a speed claim.


## First application comparison

The same manual suite now follows native qualification with `make bench-pvm-x86-applications`,
a CI-only entry into the maintained matched-image application harness. It compares current public
forced interpretation and opt-in JIT in identical binaries, an exact master/parent source,
retained-frame core and pinned PolkaVM interpreted, in both process orders. Pinky, short/long
sieve, minimal, memory fill and DOOM initialization/gameplay retain complete-state/source and
ordered host-event checks. Constructor, cold, reused and reference restoration/teardown costs
remain separate. Fresh private caches and equal-image/positive/refusal controls precede timing.

The shared output protocol retains historical `ARM_OWNER`/`ARM_JIT` record tags for parser
compatibility. Its explicit architecture and backend policy/counter receipts identify actual
x86 generation; those legacy tags make no ARM execution claim. The wrapper's exact-source
baseline is resolved before building; a baseline predating x86 generation preserves its real
checked fallback instead of pretending to have native x86 code. The first complete application cohort is recorded below.


## First qualified application cohort (before master reconciliation)

At measured candidate `fb58eabed1089997c38695e3d0453a90c0776bf4`,
[run40666408433](https://github.com/jacogr/ragnarok/actions/runs/40666408433)
passes all thirteen native gates and the complete application cohort against exact master
`a0dcebe49ddd5a1f36a12479453c0d50c034a4bb`. This runner reports AMD EPYC9V45;
it does not imply dedicated access to all cores. Both sides use pinned October26 Nimony
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`, checked release/ARC/Clang ThinLTO.
Independent raw-log and source-receipt verification passes70processes/910calls,
115positive/refusal controls,16fresh builds/eight equal-image pairs and727identities.
Report SHA256: `ba0a7ff9a297581cf42ed1b9164b0875768303f793f03aa6008c94f67c2fcc8d`.
Complete CPU/gas/register/page/permission/source snapshots and ordered host events remain required.
No hardware counters were collected.

CPU milliseconds, forward/reverse order; reused medians use samples3–12 without outlier removal.
Public calls include fresh invocation memory and immutable publication; core reset/publication
are separate. PolkaVM call clocks exclude restoration and teardown.

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.062 / 2.154 | 2.079 / 2.054 | 2.355 / 2.361 | 2.038 / 2.070 | 3.765 / 4.363 | 1.142 / 1.096 | 0.625 / 0.541 |
| minimal 100000 | 3.592 / 3.395 | 4.040 / 3.897 | 3.446 / 3.458 | 3.463 / 3.538 | 3.775 / 3.809 | 0.959 / 1.019 | 0.913 / 0.908 |
| memset 100000 | 2.741 / 2.767 | 2.829 / 2.705 | 2.824 / 2.751 | 1.918 / 1.960 | 2.628 / 2.561 | 1.030 / 0.994 | 1.075 / 1.074 |
| pinky 1 | 79.068 / 77.442 | 77.425 / 81.302 | 68.257 / 67.390 | 65.265 / 67.609 | 90.363 / 90.907 | 0.863 / 0.870 | 0.755 / 0.741 |
| sieve 10000000 | 208.112 / 203.608 | 208.542 / 204.575 | 222.669 / 218.110 | 200.342 / 200.916 | 259.270 / 261.293 | 1.070 / 1.071 | 0.859 / 0.835 |
| init 0 | 356.545 / 282.423 | 285.161 / 279.305 | 281.950 / 282.335 | 279.263 / 279.596 | 434.979 / 437.188 | 0.791 / 1.000 | 0.648 / 0.646 |
| tick 0 | 29.889 / 31.614 | 31.794 / 32.767 | 34.100 / 32.439 | 27.179 / 29.016 | 33.076 / 33.622 | 1.141 / 1.026 | 1.031 / 0.965 |

Constructor CPU and cold sample zero are separate from the reused table. Values below are
forward/reverse milliseconds; a reference guest-module constructor is not interchangeable with
our prepared-owner constructor (which captures immutable source facts).

| Case | Interpreter constructor | JIT constructor | Interpreter cold call | JIT cold call | Reference cold call |
|---|---:|---:|---:|---:|---:|
| sieve 100000 | 2.626 / 2.454 | 2.664 / 2.387 | 5.976 / 6.273 | 7.713 / 7.938 | 3.817 / 3.797 |
| minimal 100000 | 0.017 / 0.017 | 0.016 / 0.021 | 3.633 / 3.573 | 3.606 / 3.640 | 4.043 / 3.731 |
| memset 100000 | 0.051 / 0.048 | 0.049 / 0.054 | 7.936 / 6.401 | 6.575 / 6.865 | 2.667 / 2.650 |
| pinky 1 | 0.602 / 0.565 | 0.596 / 0.578 | 82.230 / 78.195 | 71.194 / 70.250 | 91.938 / 90.416 |
| sieve 10000000 | 2.421 / 2.447 | 2.391 / 2.589 | 205.271 / 208.484 | 209.931 / 211.593 | 248.886 / 235.595 |
| init 0 | 6.695 / 9.373 | 9.101 / 6.773 | 386.054 / 314.210 | 313.794 / 313.579 | 425.067 / 435.000 |
| tick 0 | 8.924 / 6.789 | 6.651 / 6.729 | 52.736 / 53.810 | 53.774 / 51.163 | 33.252 / 34.569 |

Reference reused DOOM lifecycle milliseconds (restoration / call / teardown / total), each
component's median computed independently:

- init: forward 6.878 / 434.979 / 1.272 / 443.276, reverse 6.945 / 437.188 / 1.301 / 445.347.
- tick: forward 6.667 / 33.076 / 1.163 / 41.094, reverse 6.927 / 33.622 / 1.216 / 41.883.

Verdict: keep the opt-in correctness foundation; do not enable this emitter by default yet.
Pinky improves about13% in both orders. Long sieve regresses about7%; gameplay is mixed or
slower. DOOM initialization's forward interpreter outlier is not a claimed improvement.
Minimal executes zero native operations, so its movement cannot establish a native benefit.
These historical numbers are not a new reconciled-head measurement.

The source-operation coverage is low on long sieve (about0.14%) and gameplay (about8.2%),
versus about29.8% on Pinky. These are source operations, not executed hardware instructions.
The next bounded investigation uses CI-only calibrated Callgrind over the sealed application
images, preserving thirteen complete state-checked calls, exact symbol selection, a cold dump
and the final reused dump. Public invocation memory construction/publication stay inside the
scope. Instrumented clocks are discarded; conditional/indirect misses are simulated estimates.
This separates handoff and interpreter costs from emitted register traffic before choosing
resident registers or native branch/loop coverage. Default enablement requires a qualified
useful result, with interpretation and OS-refusal fallbacks retained.


## Reconciled foundation confirmation

[Run40670585583](https://github.com/jacogr/ragnarok/actions/runs/40670585583) qualifies
`1660a045193d3b5c3b4033fa78e09b0d28f299c2` against the same exact master
`a0dcebe49ddd5a1f36a12479453c0d50c034a4bb` after native master reconciliation.
All thirteen native gates pass again; the independent application audit confirms70processes,
910checked calls,115controls,16fresh builds/eight equal-image pairs and730identities.
Application report SHA256: `d15209ac46fa363e27b9d2703524ee2b78ddca741157c9ea7a25cfdb264eaf7b`.
The runner again reports AMD EPYC9V45. These are a separate cohort, not pooled with earlier runs.
Reused CPU milliseconds, forward/reverse, with the same lifecycle boundaries:

| Case | Public interpreter | Public previous JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 2.111 / 2.142 | 2.105 / 2.083 | 2.339 / 2.147 | 2.094 / 2.119 | 3.949 / 4.045 | 1.108 / 1.002 | 0.592 / 0.531 |
| minimal 100000 | 3.497 / 3.503 | 3.511 / 3.510 | 3.465 / 3.425 | 3.566 / 3.384 | 3.846 / 3.705 | 0.991 / 0.978 | 0.901 / 0.924 |
| memset 100000 | 2.974 / 2.935 | 2.844 / 2.923 | 2.949 / 2.911 | 1.960 / 1.949 | 2.662 / 2.576 | 0.992 / 0.992 | 1.108 / 1.130 |
| pinky 1 | 80.742 / 81.559 | 79.613 / 83.758 | 70.438 / 67.691 | 69.812 / 68.534 | 91.749 / 90.290 | 0.872 / 0.830 | 0.768 / 0.750 |
| sieve 10000000 | 206.062 / 218.773 | 201.984 / 215.096 | 216.551 / 231.198 | 202.306 / 207.853 | 264.737 / 269.746 | 1.051 / 1.057 | 0.818 / 0.857 |
| init 0 | 286.234 / 295.943 | 295.493 / 287.975 | 287.934 / 279.195 | 285.382 / 283.912 | 443.346 / 441.958 | 1.006 / 0.943 | 0.649 / 0.632 |
| tick 0 | 31.612 / 31.962 | 29.927 / 33.724 | 33.266 / 32.419 | 31.753 / 29.452 | 33.963 / 35.134 | 1.052 / 1.014 | 0.979 / 0.923 |

This confirms useful Pinky improvement but a repeated long-sieve regression (about5–6%) and
mixed/slower gameplay versus the same-binary interpreter. It remains opt-in while the calibrated
public-invocation profiles investigate that cost; beating the reference on some workloads is
insufficient reason to regress our existing interpreter by default.


## Scoped foundation profiles

[Run40672822148](https://github.com/jacogr/ragnarok/actions/runs/40672822148), at
`f61365cd72ac93754177555e2b3dfd2910cf8ed3`, passes the complete same-runner application
cohort again (70processes/910calls/115controls/16fresh builds/eight equal pairs,
731identities), plus all six scoped profiles. Application report SHA256:
`b6617b42d7cd4239eaa6adf06b5d9d9abbaf9385ffada7958b7641277ba162c1`.
This head adds only the profiler and a stable public benchmark wrapper; production runtime
remains identical to the qualified foundation. Callgrind3.26.0 is calibrated for absent,
selected, repeated and final-return scopes. Profile clocks are discarded.

| Reused public call | Interpreter Ir | JIT Ir | Interpreter Bcm / Bim | JIT Bcm / Bim |
|---|---:|---:|---:|---:|
| sieve100k | 43,530,941 | 43,516,882 | 12,902 / 767,823 | 12,936 / 766,444 |
| Pinky | 1,164,383,167 | 1,095,762,687 | 1,166,872 / 28,804,893 | 1,580,376 / 23,019,049 |
| gameplay | 587,243,757 | 584,067,901 | 345,429 / 11,722,351 | 319,350 / 11,316,682 |

Ir is executed machine instructions under instrumentation; Bcm/Bim are simulated conditional
and indirect misses, not hardware measurements or explanations of CPU timing by themselves.
Cold/reused raw dumps, all controls, native working-set agreement and every exclusive event sum
independently verify. The formatter's flat self view incorrectly attributes zero-call ancestry
arcs to libc startup. The maintained parser now excludes every call-arc cost, including zero-call
ancestry, and requires exclusive event sums to match all raw footer totals. Original raw dumps
and inclusive call arcs remain retained; the misleading flat view is not hotspot evidence.

Corrected reused self costs place checked block-entry charging at14,154,240Ir for sieve100k,
211,411,400Ir for Pinky and105,479,300Ir for gameplay (roughly18–32% of their total work).
Native handoff itself costs78,104,992Ir on Pinky and16,702,504Ir in gameplay. Public memory
construction/publication remain included in the scope; sieve's call arc places97.4% of its
instructions within execution. The near-identical sieve instruction totals and low source
coverage argue for testing compiled conditional/block entries before register allocation alone.
The latest timing cohort remains mixed, including opposite-order movement on long sieve; no
new default-enable claim follows from these counters.

The next bounded runtime experiment extends only positive cached conditional capabilities and
complete pure charged blocks. Checked gas/source-prefix/error ordering, original partial handlers,
memory and genuine exits must remain unchanged. Default enablement is a later integration step.

## October 28 compiler compatibility

Reconciled with master `bf82cf784e97e9bef1b2bcb169b5759037caaf97` and its
Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` pin. `X86Arena` now
explicitly clears its native handle in a non-destroying move-reset hook. Copy and
duplication remain forbidden. Historical timing receipts below the old pin remain
historical; this change does not requalify their performance under the new compiler.

The existing CI-only native qualifier additionally moves a genuinely published
arena through a consuming call, observes its cleared source, executes the retained
entry and retires the destination, repeating 1,000 times. Its duplicate twin must
fail with the exact arena ownership-lowering diagnostic. Qualification is pending.

## Conditional/block-entry trial (qualification pending)

This dependent increment targets the measured checked-entry cost. It independently emits all
sixteen immediate/register conditional forms as full-width CMP and scalar CMOV returns. An
arithmetic leaf can promote only when its exact original conditional worker already certifies
two valid cached source destinations. A failed promotion preserves the old arithmetic entry.
Append-only storage, coordinate/byte/publication caps and exclusive code-only ownership remain
unchanged. No native memory access, host callback, unchecked target or connected loop is added.

An exact ordinary header may select a complete pure native block only when its sealed source
extent ends at that cached conditional. Full gas and source quotas are checked before debit;
resumed, partial, zero-budget and insufficient-gas cases use canonical reservation and original
source handlers. Observable exits still materialize canonical PCs. Comparison leaves retain no
invocation state and return only positive scalar stream offsets. Branch/header counters must
prove the path executed. Production defaults remain unchanged during qualification.

Tests add1,296direct conditional cases,540reused loop-prefix/gas/paid-state cases, typed return
storage controls, and preserve all existing scalar/literal/opcode/memory/host/source/ownership
checks. Qualification and same-runner paired timings against the accepted foundation are pending;
these are test plans, not passing native evidence. All native work remains on CI.


### First conditional-entry measurement: revise before default enablement

[Run40677330666](https://github.com/jacogr/ragnarok/actions/runs/40677330666) at
`b49a2e04895976cd5626abc90673ba2e964cd5f6` passes all thirteen native gates, the complete
70process/910call/115control/16build/eight-pair application cohort and all six calibrated
profiles. Independent source/raw-log/profile/native-working-set audits pass731identities.
Report SHA256: `1c20c01381e8a316b200970679c860442397258cd036d5d7adb8db305cab9b32`.
The explicit paired parent is `7d21d39a4c1c482452e5e0d009898388e26ee669`.
Runner: AMD EPYC7763, a different model from the earlier foundation cohorts; only this cohort's
own pairings are ratios. Reused public CPU milliseconds, forward/reverse:

| Case | Public interpreter | Parent foundation JIT | Public current JIT | Retained core JIT | PolkaVM interpreted call | Current / interpreter | Current / reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve 100000 | 3.987 / 3.956 | 4.541 / 4.488 | 3.893 / 3.817 | 3.766 / 3.767 | 6.042 / 6.181 | 0.976 / 0.965 | 0.644 / 0.617 |
| minimal 100000 | 6.678 / 6.716 | 7.104 / 6.981 | 6.604 / 6.599 | 6.405 / 6.547 | 7.525 / 7.522 | 0.989 / 0.982 | 0.878 / 0.877 |
| memset 100000 | 4.641 / 4.595 | 5.380 / 5.407 | 4.898 / 4.735 | 3.849 / 4.057 | 4.187 / 4.180 | 1.055 / 1.031 | 1.170 / 1.133 |
| pinky 1 | 160.856 / 163.821 | 140.381 / 146.368 | 127.584 / 128.013 | 131.936 / 121.493 | 186.008 / 178.611 | 0.793 / 0.781 | 0.686 / 0.717 |
| sieve 10000000 | 378.005 / 386.179 | 436.356 / 441.785 | 375.838 / 387.193 | 395.259 / 397.063 | 444.489 / 443.516 | 0.994 / 1.003 | 0.846 / 0.873 |
| init 0 | 757.908 / 751.752 | 562.297 / 561.514 | 762.361 / 561.070 | 562.311 / 562.350 | 775.442 / 775.050 | 1.006 / 0.746 | 0.983 / 0.724 |
| tick 0 | 58.636 / 58.118 | 55.407 / 56.307 | 60.217 / 59.437 | 47.838 / 48.623 | 53.494 / 52.613 | 1.027 / 1.023 | 1.126 / 1.130 |

Conditional entries improve sieve12–15% and Pinky9–13% versus the paired arithmetic foundation,
but gameplay regresses6–9%. Initialization has an unresolved forward-order outlier; the two
orders have identical native calls/operations/code occupancy. This is not qualified for a
production default switch. Initialization reaches1,024publications; gameplay reaches736, so
its regression cannot be attributed to a full publication cache.

Corrected reused profiles show43,530,924interpreter versus47,163,490JIT instructions on
sieve100k, and587,243,798versus623,919,864on gameplay. The whole native-entry worker costs
81self instructions per call; the branch worker costs60. These counters identify substantial
handoff work, without proving a hardware latency cause. Compared paths retain the same checked
source/gas/memory/host behavior.

The next isolated revision seals an executable callable capability during publication. Cache
records keep the exclusive mapping alive and expose no address to callers; dispatch retains
bounds, source reservation, target validation and fresh register borrows. Immutable append-only
mapping extent/alignment can then be validated once at capability creation rather than looked
up again through the arena on every transition. This revision requires fresh native/state and
same-runner timing/profile qualification; no gain is claimed yet.
