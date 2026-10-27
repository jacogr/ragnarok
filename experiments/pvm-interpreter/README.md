# Interpreter execution experiment

This branch preserves the latest locally qualified handler-stream interpreter and its supporting
memory publication implementation. Future findings can be committed here before deciding which
changes belong in the production engine. It is a learning experiment with no default-engine or
public application API change. Linux CI now qualifies this overlay; the application backend remains unchanged.

The execution organization was initially informed by the pinned PolkaVM interpreter. Complete
instruction semantics, unsigned gas, source-attempt budgets, exact exit PCs, checked memory,
immutable host snapshots and publication use our implementations and independent interpreter
cross-checks. It remains an experimental architecture with dense input-sized maps and a monotone
handler stream. [Explicit local admission limits](RESOURCES.md) now bound its components;
production deployment limits, global ownership and backend integration remain open gates.

## Source and checks

`overlay/src/pvm/experimental.nim` is the retained runtime. `machine.nim` adds batched immutable
publication to the base memory module. `run.py` materializes project sources plus these two files
under ignored `build/pvm-interpreter-experiment/snapshot`, preserving normal imports and machine
types. Production source files remain untouched. The overlay is based on
`dff50516931066f5fdd11323fc5feb645f792c26`; later base-source changes require requalification.

Run from the repository root after ordinary pinned tool setup:

```sh
make check-pvm-experimental
make check-pvm-experimental PVM_EXPERIMENTAL_FLAGS=--asan
make check-pvm-experimental PVM_EXPERIMENTAL_FLAGS='--suite all-opcodes --benchmarks'
```

The manual checks cover all 139 opcodes, aliases, high unsigned gas, source budgets, exact exit
state, fragmented checked regions, memory pairs, host reentry/repair, immutable publication epochs,
dirty bitmap boundaries, entry accounting and ARC lifetime. Assertions execute natively; source
hashes, compiler commands and complete logs stay under the dedicated ignored build directory.
CI runs every witness in separate Linux native and AddressSanitizer jobs on master pushes,
`ci:unit` / `ci:full` requests and manual unit/full runs. Both jobs gate the aggregate Unit
result and retain source hashes and diagnostic logs. Benchmarks remain explicit local runs.

Benchmark drivers are built only with `--benchmarks` and never run implicitly. They consume the
same explicit frozen input/reference files as the existing local comparisons. Kernel/lifecycle
and prefix drivers use `RAGNAROK_PVM_SIEVE_INPUT`, `RAGNAROK_PVM_SIEVE_EXPECTED` and
`RAGNAROK_PVM_GUEST`; DOOM uses `RAGNAROK_PVM_DOOM_INPUT`, `RAGNAROK_PVM_DOOM_ROM` and
`RAGNAROK_PVM_DOOM_PHASE`. The existing local evidence remains under `build/pvm-port-lab/`.
Historical comparison orchestration and generated reference artifacts are not made portable by
this source checkpoint; clean-checkout benchmark preparation remains separate work.

## Retained findings and provenance

The retained model combines native scalar stores, checked memory prefixes, cached targets,
resident host memory, sparse dirty publication, direct first-operation handoff, conditional dirty
marks, batched replacement-root publication, selected combined register workers and first-touch
block pricing. Rejected exit-derived accounting, entry specialization and other failed trials
remain absent. [Recorded results](RESULTS.md) preserve both orders and measured scope.

`provenance.json` records the original measured runtime hashes and pinned compiler/reference
revisions. This published copy changes names, comments and output labels. Prior timings describe
the original qualified binaries; newly linked images must earn their own timing evidence. The
local raw state checks, seals, load observations and rejected-trial evidence remain preserved.

The [latest campaign report](CAMPAIGN.md) contains a fresh cumulative comparison against the
starting checkpoint, both process orders against frozen master and PolkaVM interpreted,
constructor/cold/reused costs, retained changes, rejected trials and remaining production gates.
The older [results](RESULTS.md) remain a historical record of the initial checkpoint.

## Published-source checkpoint verification

On 2026-10-26, macOS arm64, all eight native witness groups and all eight AddressSanitizer
variants passed with the pinned compiler, ARC, Clang ThinLTO and runtime checks enabled. All four
published benchmark drivers compile. These are fresh builds from the materialized tracked overlay;
they do not establish new performance figures. Source hashes remain unchanged through the final
sanitizer/build run. Repository inventory, Python syntax, pinned formatting for all 14 experimental
Nim files and `git diff --check` passed. That checkpoint has no Linux qualification claim; the new CI jobs provide fresh exact-head
Linux evidence. Application integration remains separate work.

## Ongoing comparisons

The [autonomous investigation record](AUTONOMOUS.md) owns current scope, hypotheses and verdicts.
`compare.py` builds an exact committed parent and current overlay at identical source/output
coordinates with fresh private-cache repeats, then measures both process orders. Inputs and frozen
master/reference images remain explicit local dependencies. `report.py` commits compact complete
sample/phase evidence under `findings/`; raw logs and seals stay in the ignored comparison folder.
Failed measurement cohorts are preserved separately and rerun in full after harness repairs.
Run the pure Python harness contract checks with:

```sh
python3 -m unittest discover -s experiments/pvm-interpreter -p 'test_*.py'
```

The first completed comparison rejects [rare exit outlining](findings/outline-exits-qualified.md);
that isolated change was restored to the accepted checkpoint. Later findings retain
[bulk page construction](findings/bulk-page-construction.md), which improves measured gameplay
lifecycle while leaving calls essentially flat. See the investigation record for current status.

The [active-stream quota fix](findings/active-stream-barrier.md) corrects cached overlapping
suffix reentry after resets. Its exact-parent regression and minimal independent-step oracle
are preserved; this is a correctness change with no claimed timing benefit.

The 27 October follow-up retains [bounded preparation and typed admission](RESOURCES.md).
All ten native/sanitizer groups pass; the final paired cohort has 208 timed processes and four
negative controls. [Follow-up evidence](findings/resource-bounds.md) records the measured small
runtime cost, cold confirmation and both process orders. The memory/register composition trial
was rejected. Production backend wiring and deployment policy are still separate work.

## CI qualification

The PR reconciles the overlay with master `c75794e9` without changing production PVM files.
Fresh local qualification after that reconciliation passed all ten native and ten AddressSanitizer
witness groups, eight harness contracts and 47 CI safeguards. The new Linux jobs run through the
same Make entry point with ARC, Clang ThinLTO and runtime checks enabled; their actual remote
verdict remains pending until the exact PR head completes. Every requested Unit gate now requires
both profiles, including on failure, cancellation or skip.

This PR publishes the experimental engine and accumulated measurements for review. It does not
select the engine through the application backend, establish current-master performance ratios,
or make local timing drivers portable CI benchmarks. Deployment budgets, backend ownership and
application integration remain the gates described in [resource admission](RESOURCES.md).

## Linux performance comparison

The second stack layer adds an explicit `bench-pvm` workflow dispatch comparison job. It resolves
`origin/master` once on its runner and compares that exact source revision (the existing planned
interpreter) with this overlay and pinned PolkaVM interpreted. Regular master monitoring remains
separate. `make bench-pvm-experimental` owns clean-checkout provisioning; timing execution requires
Linux x86-64 and the CI environment. Local builds/parser tests require no fabricated CI variables.

The job prepares all guest states using the pinned public interpreted reference. Pinky, sieve
100,000, minimal 100,000, memory fill 100,000 and DOOM initialization/gameplay after 1,320 warmup
frames each run in forward and reverse process order. Each process retains thirteen checked calls:
index zero is cold, indices three through twelve form reused medians. Complete memory, permissions,
registers, gas, exit state, source snapshots and DOOM host-output events are checked. DOOM admission
also matches upstream frame 1,320. Every engine must reject assertion and corrupted-state controls.

Both Nim roles build twice at canonical source/output paths with fresh private compiler caches;
repeat images must match byte for byte. The report records resolved revisions, source/image/input
hashes, commands, CPU model, toolchain and every sample. Source attempts and stream occupancy are
observations, not native instruction or hardware-counter measurements. No samples are dropped.

Candidate plan/frame construction, reset, outer execution and immutable final publication are
reported separately, with a cold sum. Master planned calls include their final publication, while
its gas-plan preparation is additional. Common fixture I/O, decoding and full-state validation are
outside these scopes. PolkaVM has call-only timing; no constructor/lifecycle parity is claimed.
A failed/incomplete cohort retains diagnostics but cannot publish a successful comparison table.
