# Ordinary header dispatch

## Scope and invariant

This increment uses the existing checked reservation template directly from the main dispatch
loop when its selected worker is exactly `flatCharge`. It then fetches and executes the first
body worker. The existing `flatCharge` entry remains available to its direct callers; specialized
charged/native/failure workers retain their existing dispatch. No opcode evaluator is duplicated.

The body lookup must occur **after** reservation: a partial source-attempt budget can temporarily
replace that exact body slot with `flatBudget`, including a boundary hidden by folded no-ops.
An unstarted gas/budget failure returns the existing stop result without calling the body.
Gas order, paid flags, reserved source endpoints, exact exit PC, temporary-handler restoration,
host/fault publication and callback budgets all use the unchanged helpers.

There are no new frame fields, owner resources, source operations, native instruction words,
native publication slots, ABI changes or unchecked accesses. Single-step dispatch remains the
independent bounded adapter. GP 0.8.0 and existing PVM contracts remain authoritative; the
compiler/runtime pins and checked ARC/Clang ThinLTO profile are unchanged.

## Why this target

A five-second local sampling screen of the qualified ARM runtime repeated validated public
DOOM tick calls in each backend. Filtering all `runPreparedDoom` stack subtrees excludes the
outside-clock full-state verification. Among 1,955 JIT and 2,280 interpreter public-call samples,
`flatCharge` self weight was 10.3% / 14.3%; dispatch self weight was 8.1% / 13.7%.
This selects a shared dispatch boundary to investigate; sample weights are not projected gains.
Full stacks and parsing methodology are retained under ignored `build/pvm-doom-current-profile/`.

## Local ARM evidence, 2026-11-01

Shipping parent is repaired master `8357775578acaa1c08045fe83e6d8980aaaaae3e`.
The local source baseline `33bfc96ceed938f8ff1dab7636ceb05856097cd7` has exactly the same runtime;
the intervening merges/repair change evidence, tooling fixtures and workflow routing.
Apple M1 Max uses pinned checked Nimony
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, ARC and Clang ThinLTO.

Eight fresh canonical-path application builds pass four duplicate-image controls. Four balanced
fresh processes per source role each execute thirteen validated prepared public calls. Process
CPU medians use samples 3:13; the table takes the median across processes. Two fresh PolkaVM
interpreted reference processes provide the matched raw denominator. All public calls validate
complete CPU, pages, source immutability and events; all restoration work stays inside the clocks.

| Workload/backend | Baseline CPU ms | Candidate CPU ms | Change |
|---|---:|---:|---:|
| DOOM init JIT | 119.270 | 116.323 | -2.47% |
| DOOM init interpreter | 242.376 | 240.884 | -0.62% |
| DOOM tick JIT | 16.100 | 15.911 | -1.17% |
| DOOM tick interpreter | 24.529 | 23.872 | -2.68% |
| Minimal JIT | 4.242 | 4.226 | -0.39% |
| Pinky JIT | 65.912 | 63.659 | -3.42% |
| Memset JIT | 2.565 | 2.514 | -2.02% |
| Sieve 10m JIT | 202.833 | 203.123 | +0.14% |

All four interpreter tick, Pinky and memset process pairs improve. Three of four JIT tick and
init pairs improve; their aggregate ranges overlap, with candidate outliers. Pinky ranges do
not overlap. Minimal and sieve changes are inconclusive. Matched local raw DOOM tick ratios,
ours / PolkaVM interpreted, are **0.364 JIT / 0.547 interpreter**; init is **0.169 / 0.351**.

The initial separate tick-only gate also had four balanced processes per source role and two
references: JIT -4.92%, interpreter -2.88%, all four pairs faster. The broader table is the
shipping estimate; do not promote the larger initial JIT number as the established gain.
Both cohorts preserve native fragments/calls/operations/code bytes/branches/headers exactly
between source roles, excluding compilation time. Interpreted native counters remain zero.
All 94 process logs independently reparse through the strict application/policy parsers.

## Validation and qualification boundary

The maintained eleven-record native/refusal qualification passes on the candidate, including
opcode/alias literals,
gas/partial/paid source attempts, folded boundaries, repricing, terminal/host/fault behavior,
native memory/region controls and ownership/ARC transfer. Existing shared checked workers
remain the independent single-step comparison. The supported default-backend all-opcode
and host/memory suites pass. The final runtime file
is byte-identical to the measured candidate and passes the pinned formatter.

The added handler comparison also runs for specialized/native workers; the qualified total
application results below include that cost.
No x86 performance claim or full blockchain throughput claim is established here.

Ignored evidence: `build/pvm-header-dispatch/`, including `build.json`, original gate build
metadata, both raw cohorts, native witness and supported unit logs, and `local-reparse.json`.
Initial tick raw SHA-256:
`99b40e73166f68f71abe11a806cdd7f38e0973cf3e02efb5720e74818b0343bd`.
Broader raw SHA-256:
`503078e6cd7250120128105f139f6b7ac2a372c29e3f807370bebfb355258798`.
Measured `handler_stream.nim` SHA-256:
`97df342dd50889c1b74296f3d9f9b0a4b078b9f7de1ab7103d62f9ca95ac69f9`.

## Focused Linux ARM qualification

Exact runtime head `000d58fa1c0c4c825fa53c753d8cd4035c4e0611` passed the single-runner
[ARM replay run 41321897433](https://github.com/jacogr/ragnarok/actions/runs/41321897433)
against repaired master `8357775578acaa1c08045fe83e6d8980aaaaae3e`.
The existing artifact is `pvm-comparison-arm64-1` (ID `13089911487`). No broad CI labels were added.

Six fresh processes per JIT role each perform thirteen checked public calls. Each process value
is its CPU median over samples 3:13; these rows take the median across six process values.

| Workload | Baseline CPU ms | Candidate CPU ms | Change | Faster pairs |
|---|---:|---:|---:|---:|
| DOOM init | 149.939 | 148.970 | -0.65% | 5/6 |
| DOOM tick | 24.282 | 24.148 | -0.56% | 6/6 |
| Minimal | 5.541 | 5.555 | +0.25% | 1/6 |
| Pinky | 83.250 | 82.692 | -0.67% | 6/6 |
| Sieve 10m | 268.222 | 269.662 | +0.54% | 0/6 |

DOOM tick and Pinky process ranges do not overlap. Sieve's slower ranges also do not overlap:
this is an observed cost, rather than an inconclusive flat result. Init and minimal ranges overlap.
The primary cohort's two processes per interpreted role show DOOM tick -0.45% and init -0.12%;
that smaller cohort does not establish the same replication strength as the JIT rows above.
Its other observed interpreter costs include minimal +0.84% and Sieve +1.11%. Primary memset
changes are -2.53% JIT and -0.10% interpreter, also from two processes per role.
Matched primary raw DOOM tick ratios, ours / PolkaVM interpreted, are **0.601 JIT / 0.749 interpreter**;
init is **0.236 / 0.513**. These ratios use only matched primary timings, not replay medians.

The modest DOOM/Pinky improvements and removal of an ordinary indirect dispatch justify this
increment with the Sieve cost explicitly retained. The local larger improvements are not promoted
as the portable result. All 144 primary/replay logs and 138 controls independently audit, with
18 fresh-image equalities and 14 cross-source native activity comparisons. Native code bytes and
all execution counters agree across source roles; interpreted native counters remain zero.
Current source hashes, protocol framing, fresh-process schedule and complete-state checks pass.
The independent reviewer audits the same artifact; a final documentation-only update does not
change the qualified runtime. No x86 or full-block throughput claim follows.

Ignored audit: `build/pvm-header-dispatch/ci-arm-audit.json`.
Artifact report SHA-256:
`5b680e038aa1a14924de57c4574073025d3727c85312d80ae9947eaf50bf13c2`.
