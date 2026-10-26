# Interpreter execution experiment

This branch preserves the latest locally qualified handler-stream interpreter and its supporting
memory publication implementation. Future findings can be committed here before deciding which
changes belong in the production engine. It is a learning experiment with no default-engine or
public application API change. No PR or CI job is part of this checkpoint.

The execution organization was initially informed by the pinned PolkaVM interpreter. Complete
instruction semantics, unsigned gas, source-attempt budgets, exact exit PCs, checked memory,
immutable host snapshots and publication use our implementations and independent interpreter
cross-checks. It remains an experimental architecture with dense input-sized maps and a monotone
handler stream; bounded total cache admission and production integration remain open gates.

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
These checks are opt-in and have no automatic CI wiring.

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

The latest saved DOOM gameplay calls were 29.465/29.295 ms versus PolkaVM interpreted
35.019/35.092 ms; reused initialization was 753.236/739.498 ms versus 679.618/681.236 ms.
Those are call-only forward/reverse observations from the original images, not whole-client or
new-checkout measurements. Preparation, reset and final publication are separately recorded.
Next investigation: initialization block-charge/dispatch work, one hypothesis at a time.

## Published-source checkpoint verification

On 2026-10-26, macOS arm64, all eight native witness groups and all eight AddressSanitizer
variants passed with the pinned compiler, ARC, Clang ThinLTO and runtime checks enabled. All four
published benchmark drivers compile. These are fresh builds from the materialized tracked overlay;
they do not establish new performance figures. Source hashes remain unchanged through the final
sanitizer/build run. Repository inventory, Python syntax, pinned formatting for all 14 experimental
Nim files and `git diff --check` passed. Full Linux CI and application integration are not claimed.

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
the runtime remains exactly the accepted checkpoint after that trial.
