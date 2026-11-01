# Resident ARM register traffic

## Scope and proof

GP 0.8.0 semantics, the pinned Nimony checked ARC/Clang ThinLTO profile and existing
gas/attempt/host contracts remain unchanged. This increment starts from merged master
`9b5db44959203a2ae67e04f9637a15460b8c213e`. It changes only ARM resident-region register
transfers, with no context ABI, frame fields, owner lifetime, native entry limit or arena change.

The existing two/three-block region loaded and stored all thirteen guest registers at its
boundary. Its block-local read/write masks already describe the lowering, but simply taking
ordinary live-ins would be incorrect across branches and early guards. Initialize the union
of every member's reads **and writes**, then publish the union of writes at every exit.
Consequently every lane an early exit can store already contains its original guest value,
including a register written only by a later block that never executes. Slots outside the union
are never accessed. Internal paths still operate on the same resident register assignments.

The independent dirty-memory loop additionally includes its explicit address-base input. Its
optional word path includes all five named inputs and all three possible writes. The byte-store
emitter records its value operand as a read: the stored register need not be produced by the
arithmetic prefix. This is essential for a store-only live-in. Read-only inputs remain unchanged;
unstarted gas/attempt/memory guard exits still publish no guest mutation.

All label/fixup positions are computed from the resulting word sequence. Existing source
coordinates, conditional destinations, paid/partial/repriced fallback workers and invocation
pointer lifetimes remain unchanged. Published code stays inside its existing exclusive arena;
the 1,024-publication and 1 MiB bounds are unchanged.

## Behavioral validation

The local focused native qualification passes all eleven existing groups, including actual
native and explicit OS refusal, physical capacity/refusal, all-opcode whole-state comparisons,
host/mapping reentry and frame/stream ownership controls. Existing literal controls include
3,546 connected cases, 486 price cases, 704 region layouts, 840 dirty-loop cases, 698 word
cases and 110 word aliases, plus partial/resumed/repriced execution and owner retirement.

The witness adds 156 behavioral cases with independent store inputs in guest slots 6 and 12.
Distinct high-bit sentinels poison all registers; six complete calls cross the existing
64-backedge native admission threshold. Native coverage is required when executable memory
is available. Literal byte expectations check the stored value independently of either
engine, and complete single-step comparisons check all registers/pages/exit state across
gas and partial-attempt boundaries. The same controls pass explicit native refusal.

## Local ARM evidence, 2026-11-01

Apple M1 Max, checked pinned compiler
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, canonical paths/flags and frozen full-state
fixtures. Eight fresh application builds pass four duplicate-image controls. Each source role
uses four balanced fresh processes, thirteen prepared public calls per process; CPU process
medians use samples 3:13, then the table takes the median across processes. Two fresh PolkaVM
interpreted reference processes supply the matched raw denominator. All public calls retain
complete CPU/page/source/event checks. The shipping runtime bytes are exactly the measured
candidate, including after pinned formatting.

| Shipping comparison | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init JIT | 118.748 | 119.320 | +0.48% |
| DOOM tick JIT | 16.793 | 16.142 | -3.88% |
| Minimal JIT | 4.167 | 4.221 | +1.30% |
| Pinky JIT | 65.867 | 66.207 | +0.52% |
| Memset JIT | 2.581 | 2.582 | +0.07% |
| Sieve 10m JIT | 209.948 | 202.434 | -3.58% |

All four paired JIT tick and sieve directions improve, with nonoverlapping source-process
ranges. Interpreter tick +0.48% and init -0.18% are inconclusive. The small workload costs
remain visible; Linux qualification must assess the complete shipping change. Matched local
raw tick ratios, ours / PolkaVM interpreted, are 0.369 JIT / 0.559 interpreter.

A separate startup-selected **same-executable** emission-policy experiment passes four fresh
builds/two duplicate-image controls and another 76 full-state processes. It changes only
which resident load/store masks the JIT emits; the environment control is private and does
not ship. JIT tick improves 17.226→16.468ms (-4.40%, all four pairs faster, aggregate ranges
overlap slightly); init is flat (-0.05%). Sieve improves 2.98%, with three faster pairs and
one outlier. Other same-image differences are small/inconclusive. This supports an emitted
native-code effect beyond changing the C executable; native arena layout also changes, so
the entire measured benefit cannot be assigned solely to fewer register loads/stores.

Both cohorts preserve fragments/calls/operations/branches/headers exactly between source or
policy roles; compilation time is excluded. Published native code shrinks 68 bytes for init,
72 for tick and 76 for sieve, while Pinky/memset code bytes are unchanged. Interpreted native
counters remain zero. All 152 local process logs reparse through the strict application and
policy parsers.

Ignored evidence: `build/pvm-resident-register-masks/`, including `final-native/results.json`,
`build.json`, `same-image-build.json`, `local-reparse.json` and both raw cohorts. Shipping raw
SHA-256: `3a740ea5f1bae142cc55d0207a64209816e8ce83d15cc1492e27d84aecb5204c`.
Same-image raw SHA-256: `fc3649bf6a8a977ffbc7b0d8c661b672eea55aab003b15dce5c7553ea4d21bc4`.
Runtime `arm64_jit.nim` SHA-256:
`934b75a39afcd6e46c7016c37a3d13695a2e9de72c88920b2cefe2be751f181f`.

The local results above are qualified on Linux ARM below. No x86 timing claim, compiler change,
relaxed check, additional native publication or new guest coverage is included.

## Linux ARM qualification, 2026-11-01

Exact runtime head `438a1efc696061b3977e5256031bff1fc8452d25` passes the focused
[ARM replay run](https://github.com/jacogr/ragnarok/actions/runs/41310635830) against
`9b5db44959203a2ae67e04f9637a15460b8c213e`, with the same pinned checked compiler.
Artifact `13086255442` contains 20 fresh builds, 84 primary processes, 138 positive/refusal
controls and 60 additional JIT replay processes. Author and independent reviewer reparse all 144
primary/replay logs and 138 controls, 18 fresh image equalities and current source hashes.
All 14 native-work pairs preserve fragments/calls/operations/branches/headers, with the expected
smaller code size; within-source replays preserve code size too. Native/refusal controls both
execute the 156 store-only live-in cases. Existing native ownership/memory/region/priced
controls pass. Interpreted native counters stay zero.

Each JIT entry below is the median of six process medians using CPU samples 3:13.

| Workload | Baseline JIT ms | Candidate JIT ms | Change |
|---|---:|---:|---:|
| DOOM init | 146.513 | 148.866 | **+1.61%** |
| DOOM tick | 24.890 | 24.032 | **-3.45%** |
| Minimal | 5.497 | 5.553 | **+1.01%** |
| Pinky | 83.445 | 83.157 | -0.34% |
| Sieve 10m | 272.272 | 268.174 | **-1.50%** |

All six tick and sieve pairs improve with nonoverlapping process ranges. All six init pairs
regress with nonoverlapping ranges. All six minimal pairs regress, with aggregate ranges
overlapping; Pinky improves in five pairs with overlap. The primary two-process interpreter
comparison is flat for DOOM: tick -0.063%, init +0.085%. It has less replication than the JIT
replay table. Matched primary raw ours / PolkaVM interpreted ratios are **0.600 JIT / 0.752
interpreter** for tick, **0.237 / 0.513** for init; primary numerators use their matching
reference, rather than a replay numerator paired with another cohort's denominator.

The gameplay gain and lower resident boundary traffic support adoption, with the init and
minimal regressions explicitly retained as costs. This is not a uniform speedup and does not
establish full blockchain throughput. Native code layout changes alongside the fewer transfers.
The final qualification update changes this evidence document only; runtime remains the
measured head above, so no additional cohort is needed for that documentation update.

Application report SHA-256:
`0ac39996e2f3008b86ea852fd523da49e8243263e129aff01156acb762f90903`.
Artifact ZIP SHA-256, independently recorded by review:
`2e5df04c2fe7dea3a767a67f816fbe8caa0920f2886673c895025f43e4bf24fd`.
Ignored author audit: `build/pvm-resident-register-masks/ci-arm-audit.json`.
