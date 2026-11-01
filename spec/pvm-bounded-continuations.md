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
interpreter pair qualifies the public head below; no broad CI labels are needed.
No x86 performance claim is established.

## Focused Linux ARM qualification

Exact runtime/tests/controller head `e0d4b76cad04a0efda20f5324430a58bf8fff5d4` passes the
single-runner [ARM qualification and replay run 41352469098](https://github.com/jacogr/ragnarok/actions/runs/41352469098)
against master `048a21324c620ebe1fb921fd8434c0b695c9dd5c`, including the explicit interpreter
pair. Artifact `13102836079` retains the complete evidence. No broad CI labels were added.

The primary interpreter cohort has **two fresh processes per source role**, each executing
thirteen complete-state public calls. Process values use CPU medians over samples 3:13;
the following values take the median across the two processes.

| Workload, interpreter | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init | 319.382 | 317.044 | -0.73% |
| DOOM tick | 28.553 | 27.583 | -3.40% |
| Minimal | 5.563 | 5.531 | -0.58% |
| Pinky | 90.434 | 86.589 | -4.25% |
| Memset | 3.426 | 3.444 | +0.53% |
| Sieve 100k | 3.078 | 3.099 | +0.68% |
| Sieve 10m | 321.198 | 324.584 | +1.05% |

Every interpreter case has both pairs in the displayed direction and nonoverlapping ranges.
The Sieve direction reverses the small local improvement: both Sieve sizes and memset are
observed Linux interpreter costs. This two-process primary cohort has less replication than
the separate six-process JIT replay.

| Workload, six-process JIT replay | Baseline CPU ms | Candidate CPU ms | Change | Faster pairs |
|---|---:|---:|---:|---:|
| DOOM init | 145.997 | 145.831 | -0.11% | 4/6 |
| DOOM tick | 21.147 | 21.086 | -0.29% | 5/6 |
| Minimal | 5.225 | 5.275 | +0.96% | 0/6 |
| Pinky | 82.543 | 81.931 | -0.74% | 6/6 |
| Sieve 10m | 276.878 | 274.148 | -0.99% | 6/6 |

Pinky and Sieve JIT replay ranges do not overlap. Both DOOM cases and Minimal overlap;
Minimal nevertheless has all six pairs slower. No causal JIT DOOM gain is attributed to this
interpreter change. The two-process primary-only JIT controls additionally show memset
3.275 to 3.308 ms (+0.98%) and Sieve 100k 2.713 to 2.739 ms (+0.95%), both pairs slower with
nonoverlapping ranges. Neither small control has a six-process replay.

Matched **primary** raw ratios, ours / PolkaVM interpreted, are **0.522 JIT / 0.689 interpreter**
for DOOM tick and **0.232 / 0.503** for init. No replay numerator is mixed into these ratios.
The complete DOOM interpreter benefit and fixed-depth dispatch improvement justify this
increment with the measured control-workload costs retained. No universal gain, x86 timing or
full-block throughput claim follows.

Independent author and reviewer audits pass all 84 primary plus 60 replay process logs,
42 positive and 96 negative controls, eighteen fresh-image equalities, source identities and
complete state checks. All fourteen primary cross-source native-work/code comparisons are
exactly equal, and replay work/code agrees with each corresponding primary role. All interpreted
native counters remain zero. All eleven native/refusal/ownership records, both runtime-policy
suites, positive owner moves, intended copy-refusal reasons and both new 120-case long receipts
pass. The author additionally verifies all 2,575 role source hashes, 519 native source hashes
and all thirty-two recorded fixture identity files; the reviewer verifies the twenty-four
pinned workload inputs. The final evidence-only update changes no qualified runtime, test,
controller or fixture source.

Ignored author evidence: `build/pvm-bounded-chain/ci-arm/`, `ci-arm-audit.json` and
`remaining-audit.json`. Official artifact ZIP SHA-256:
`6449751c571a603e57ca0bced27e34c375e4bfee43ac52f344e4c53991e6e732`.
Application report SHA-256:
`926bc84c6f1d0b5f65fb3e3abd4f61fad403319fa0e27ed57fb7f081473c9876`.
Native report SHA-256:
`a4f65f206edf1301e20dbf991234d409ba5e32b15808e3dbf0157e13114bce4b`.
