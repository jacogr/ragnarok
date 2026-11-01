# Bounded interpreter continuations

## Architecture and semantic boundary

Ordinary interpreted stream emission now allows up to three continuing prefix workers before
an original worker returns to the main dispatch loop. This raises the fixed chain bound from
two to four physical stream nodes. Native-enabled ARM64 and x86-64 plans retain the original
exact two-node pairing layout; explicitly interpreted plans and builds without native support
use four. The bound is a preparation choice, not another runtime field or public setting.

The current interpreter profile identifies main dispatch and memory/register handoffs as
material costs. Longer bounded chains reuse the existing register/memory pair workers and
selected two-opcode fusions. They avoid some returns through main dispatch without relying
on the compiler to implement tail calls. This is deliberately bounded handler composition;
there is no unbounded recursive threading or new opcode evaluator.

Emission counts every non-folded physical node. After three selected continuation prefixes,
the next node keeps its original handler and resets the counter. Folded no-ops emit no node.
A fused worker returns after its two source operations, so it cannot extend the call chain.
Entry at an addressable interior node runs only a suffix of the bounded chain. Callee helpers
can add fixed C frames: four is a bound on composed stream nodes, not on every C stack frame.
The structural bound is independent of block length and sibling-call optimization.

Pair workers still read the next handler at execution time. A partial reservation can therefore
replace any addressable source boundary with the existing budget handler. Fused workers retain
the explicit barrier check before reading or changing their second operands. Errors, memory
permission/refusal checks, exit PCs, gas, source-attempt accounting and host transitions remain
owned by the existing workers. Pricing, ownership, native instruction emission, ABI, frame
state, source limits and resource lifetimes do not change. GP 0.8.0 and the existing PVM
contracts remain authoritative.

## Correctness controls

The maintained complete-state witness now includes two independent 8,194-source blocks, each
with 120 combinations of paid/unpaid entry, gas and attempt boundaries. One exercises existing
add/add fusion. The other alternates genuine add-immediate and move-register opcodes, avoiding
that fusion and exercising actual longer handler chains. Each compares against the Step oracle;
complete runs also check literal final register values. Both explicitly disable native execution
inside native and forced-refusal builds.

The same full witness and both long programs pass checked ARC builds with
`-fno-optimize-sibling-calls` and LTO disabled. Actual disassembly contains indirect `BLR` calls
in register-pair workers. These execution checks validate the long programs without assuming
compiler tail-call optimization; the emission bound above establishes constant chain depth.
The normal native, refused and plain witnesses also pass. The native controller requires exactly
one complete 120-case receipt for each shape in every mode. Python fixtures include both valid
receipts, with independent missing, truncated and duplicate negative controls in all three modes.

## Local ARM measurements, 2026-11-01

Baseline is current master `048a21324c620ebe1fb921fd8434c0b695c9dd5c`.
Apple M1 Max uses pinned checked Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, ARC
and Clang ThinLTO, with bounds checks enabled. Eight fresh canonical application builds pass
four duplicate-image controls. Four balanced fresh processes per source/backend execute thirteen
validated prepared public calls. A process value is the CPU median of samples 3:13; each table
value is the median across four processes. Two matched PolkaVM interpreted reference processes
supply each raw denominator. Complete CPU/pages/events and immutable-source checks remain in
every public call, with lifecycle restoration inside the collected clocks.

| Workload, interpreter | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init | 239.782 | 239.283 | -0.21% |
| DOOM tick | 22.725 | 21.740 | -4.34% |
| Minimal | 4.535 | 4.544 | +0.18% |
| Pinky | 80.983 | 79.584 | -1.73% |
| Memset | 3.677 | 3.691 | +0.38% |
| Sieve 10m | 328.907 | 327.943 | -0.29% |

All four DOOM tick, Pinky and Sieve interpreter pairs improve with nonoverlapping aggregate
ranges. Init, Minimal and memset have mixed pairs and overlapping ranges: their small point
estimates do not establish a general gain or regression. The separate initial 36-process
DOOM gate showed interpreter tick 23.093 to 22.582 ms (-2.21%), also all four pairs faster with
nonoverlapping ranges. Its raw measurements remain separate from the broader 108-process cohort.

The broader JIT controls are DOOM init -0.11%, tick -0.71%, Minimal +0.26%, Pinky +0.04%,
memset -0.32% and Sieve -0.03%, all with overlapping ranges. Initial JIT tick was +0.11% with
mixed pairs. No JIT tick speedup is established by these local cohorts. Within each workload,
native fragments/calls/operations/code bytes/branches/headers remain exactly equal across
source roles, excluding compilation time; all interpreted native counters are zero.

Matched broader raw ratios, ours / PolkaVM interpreted, are **0.320 JIT / 0.502 interpreter**
for DOOM tick and **0.166 / 0.346** for init. These are local complete-application measurements,
not a portable or full-block throughput claim.

An independent private eight-node variant passed the same functional and duplicate-image
controls. Against four nodes, its DOOM interpreter tick was +0.32% with mixed pairs and
bimodal overlapping ranges, while init was +1.32%, all four pairs slower with nonoverlapping
ranges. It is not promoted. Four is the measured choice here, not an assertion that every
workload or architecture has the same optimum.

## Evidence and qualification

Ignored evidence is retained under `build/pvm-bounded-chain/`, including both raw cohorts,
strict reparse, cross-source native work/code and paired-range audit, canonical source/image
identities, complete mode/policy checks, long-block logs and no-sibling disassembly. The rejected
eight-node comparison is separate under `build/pvm-bounded-chain-eight/`.

Initial 36-process raw SHA-256:
`363dd1586d4616647b49ad40c8e1b606d462141e3e0f81469434ba4a738efb12`.
Broader 108-process raw SHA-256:
`27daf275dd95461953c1eec7751134ccd69db6e972423568a059682d57534ab4`.
Formatted runtime `handler_stream.nim` SHA-256:
`38d93eab4ad2475ff7c8b5d359a79c22c701110befd8bd7f77e8c30ce61be74c`.

The exact formatted promoted source passes all eleven maintained native/refusal/ownership
qualification records, both backend policy suites, pricing ownership and the plain full witness.
The maintained default all-opcode, regions/host and pricing-owner Make suites also pass, along
with all seventeen native-controller Python tests. One focused Linux ARM run with the explicit
interpreter pair will qualify the public head before readiness; no broad CI labels are needed.
No x86 performance claim is established.
