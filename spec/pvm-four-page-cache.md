# Four-page scalar-cache experiment: rejected

## Scope and hypothesis

Baseline: `6cdda51bc57abe5496409354c0d53265432ee02e` (DOOM evidence above PR1607).
Keep the pinned Nimony/PolkaVM toolchains, checked ARC/Clang ThinLTO builds and exact
DOOM initializer/gameplay snapshots from [DOOM attribution](pvm-doom-attribution.md).
Change only the existing scalar writer's recent-page cache from two to four slots,
with bounded duplicate-free recency promotion. Slot/index validation, permissions,
protected-prefix/overflow/presence ordering, cross-page preflight and COW remain intact.
No permission cache, new decoded representation or frame-inlining annotation.

Hypothesis: four slots retain interleaved gameplay pages that currently cause
sparse-page binary searches. No hit rate or performance benefit is assumed.

## Acceptance gates

First collect complete-state/output-validated instruction profiles without clocks
using the opt-in `profile-doom` workflow with `pvm_doom_counts_only=true`.
Compare against qualified baseline instruction profiles in CI40187719956, including
identical reference binaries/counts, guest memory-operation totals and output hashes.
Require at least eight fewer total native instructions per gameplay memory access,
a clear reduction in mapped search work and no initializer instruction regression.
Baseline gameplay: 1,951,800,802 instructions / 2,652,585 guest memory operations;
initializer: 26,741,550,265 instructions. Preserve strict refusal/scope controls.

Only on passing that counter gate, compare baseline/candidate DOOM timings on one CI
runner in both process orders and run the maintained full paired matrix with
identical-source controls. Require repeatable gameplay improvement beyond control
variation and no reproducible regression above 2% on fill, indirect, host/cross-page
or memo controls. Stop and record rejection on failure. Local runs remain untimed.

## Status: rejected

The instruction gate passed, but paired CI CPU timings failed. The four-slot runtime
change is reverted; no additional cache variant or broader timing matrix is run.
Local checked suites pass: scalar writer (including five-page pressure), memory
chunks, machine, memory step, metered cross-page retry and host-memory re-entry.
All 67 focused tooling/profile/workflow tests, pinned formatting and verification
inventory pass. Untimed DOOM admission is recorded with the candidate revision.

## Instruction gate: passed

[CI40190229469](https://github.com/jacogr/ragnarok/actions/runs/40190229469)
measures `edb6d8c1f91c30ed3118421fdabc45ada8fae337` on AMD EPYC 7763.
No timing samples were collected. All raw/source hashes, complete input/output
identities, reference binary and all reference counters match the qualified baseline;
all ten correctness/scope controls pass. Guest memory-operation counts are unchanged.

| Phase | Baseline total Ir | Candidate total Ir | Change | Saved Ir/access | Mapped search Ir, baseline → candidate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Initialization | 26,741,550,265 | 26,672,752,778 | -0.2573% | 8.446 | 315,638,980 → 149,514,344 |
| Gameplay | 1,951,800,802 | 1,928,999,129 | -1.1682% | 8.596 | 189,472,721 → 113,459,949 |

All three counter gates pass. Search savings are partly offset by additional cache
bookkeeping; the total reduction is much smaller than the search-body reduction.
Proceed to paired CI timings; no CPU-time benefit is established by these counters.

## Paired timing method

`make compare-pvm-doom PVM_COMPARE_BASE=<baseline>` prepares the same complete
1320-tick gameplay fixture, then compiles both exact library commits using the
current shared DOOM driver. Four sequential fresh builds use one canonical source,
output and compiler-cache path; the cache is removed between builds, and the images
are saved before the next build. Candidate and both independently built candidate
controls must be byte-identical before any clocks are enabled. Equal library
endpoints must also produce equal baseline/candidate images. Every image passes
full initializer/gameplay state and output checks plus an assertion refusal.

The opt-in `compare-doom` job fetches complete Git history and runs 20 ordered
processes: initializer/gameplay × both process orders × baseline, candidate,
reference and two identical-image controls. Each process restores/validates thirteen
complete calls (three warmups, ten retained CPU samples). Reported medians and
ratios are independently reparsed from raw strict-framed stdout. Input, source,
compiler and binary hashes remain fixed during execution. Local
`PVM_DOOM_COMPARE_CHECK=1` performs admission/build/image/refusal checks with no
clocked calls. The maintained `compare-pvm` job separately provides its full paired
matrix, identical-image controls and pinned-reference comparison.

Local paired admission passes four fresh builds, complete initializer/gameplay
validation and four assertion refusals. Candidate and both control binaries match
byte for byte. The paired parser/workflow/snapshot/local-clock safeguards and
existing comparison tests pass (95 focused tests); no local guest timing samples.

## Paired CPU gate: rejected

[CI40191775253](https://github.com/jacogr/ragnarok/actions/runs/40191775253)
measures frozen candidate `5fff97ce1060bb63e046ed9e17071317a0eddaff` against
baseline `6cdda51bc57abe5496409354c0d53265432ee02e` on Intel Xeon Platinum 8573C.
Runtime source is byte-identical to instruction-gate candidate `edb6d8c1`.
All 20 ordered processes / 260 complete calls pass validation. Both independently
rebuilt candidate controls are byte-identical to the measured candidate. Raw logs,
source commit identities, fixed input/output/golden hashes and recomputed CPU
medians/ratios independently replay successfully.

| Phase | Order | Baseline CPU ms | Candidate CPU ms | Change | Same-image control change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Initialization | 0 | 1301.720 | 1433.937 | +10.157% | -0.097% |
| Initialization | 1 | 1301.946 | 1436.868 | +10.363% | +0.146% |
| Gameplay | 0 | 95.974 | 100.048 | +4.245% | -0.261% |
| Gameplay | 1 | 95.316 | 99.851 | +4.757% | +2.722% |

On this same runner, baseline/reference gameplay CPU ratios are 3.882× / 3.870×;
candidate/reference ratios are 4.046× / 4.054×. Initialization ratios are
2.171× / 2.180× baseline versus 2.392× / 2.406× candidate. Ratios from different
CPU models must not be compared as optimization deltas.

Fewer instructions do not establish fewer cycles. The mapped binary-search saving
is real, but added four-slot probing/recency work and resulting generated-code
changes fail the CPU gate. These measurements do not isolate the hardware cause
among calls, dependency chains, branches or cache behavior; no such claim is made.
The gameplay slowdown appears in both orders, and initializer regression greatly
exceeds its controls. Reject and stop; the maintained full matrix is not needed to
rescue an already failing target workload. The existing two-slot runtime is restored
exactly, while reusable counts-only and paired-DOOM tooling plus stronger sparse-page
pressure coverage remain available for future investigations.

Final runtime tree matches baseline `6cdda51b` exactly (`src/pvm` has no diff).
The retained five-page pressure test also passes after restoration, including
1,000 ARC ownership cycles with unchanged occupied memory. No measured improvement
is claimed or retained for four-slot caching. The diagnostic tooling is the final
reviewable change.
