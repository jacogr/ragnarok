# Four-page scalar-cache experiment

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

## Status

Candidate implementation is ready for the instruction gate; no win claimed.
Local checked suites pass: scalar writer (including five-page pressure), memory
chunks, machine, memory step, metered cross-page retry and host-memory re-entry.
All 67 focused tooling/profile/workflow tests, pinned formatting and verification
inventory pass. Untimed DOOM admission is recorded with the candidate revision.
