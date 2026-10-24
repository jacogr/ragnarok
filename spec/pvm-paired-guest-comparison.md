# Paired interpreter revision comparisons

## Scope and reproduction

`make compare-pvm-guests PVM_COMPARE_BASE=HEAD^` compares the selected local
revision's PVM/codec library sources with the current working sources. Both use
one frozen copy of the current maintained guest driver and clock header, checked
Nimony ARC/Clang ThinLTO, the same flags, frozen guest artifacts and independently
prepared full states. The selected ref resolves to an immutable commit once;
subsequent Git reads use that commit. Historic build scripts/harnesses are not run,
no dependency/toolchain pin changes, and no compiled backend is enabled.

The default bounded matrix is sieve/indirect-call/memory-fill at1,000 and100,000,
plus one initialized Pinky frame. `PVM_COMPARE_SCOPE=controls` explicitly selects
the six non-Pinky inputs. The default has1,092 validated native invocations;
the controls have936. The normal public-reference benchmark is unchanged. A baseline incompatible with the current driver fails explicitly rather
than adapting its APIs or changing the reference expectation.

## Shared inputs and identity

The real-guest census and comparison share one input-preparation helper. It verifies
all declared fixture members, including licenses/manifests for unselected families,
checks upstream provenance, and builds the pinned interpreted reference offline after
Make's fetch. Each preparation must produce one exact family/size record with
canonical bounded page/code counts, plus nonempty initial/expected state files.
One preparation per case supplies both endpoints. Preparation timings are not
interpreter performance samples.

Private snapshots contain owned PVM modules, their natural codec and the identical
current driver/header. Existing source-only snapshot directories are retired before
reuse, so a deleted module cannot survive from an earlier run. Traversal, foreign
source symlinks and unsupported source trees are refused. Compiler caches remain
separate from snapshots and endpoint build profiles include their source directories.
Both built executables must fail the maintained assertion control with the exact
failure marker; a zero exit or unrelated failure refuses the comparison.

Full source, driver, tool, pin, fixture, generated input, compiler and binary hashes
are rechecked before publishing. Working-source module membership is checked too.
A mutation invalidates the whole aggregate, including earlier passing samples.
The baseline commit is provenance; candidate HEAD is only context, while hashes
identify the actual working sources, including uncommitted owned modules.

## Samples and publication

Every pricing mode runs in fresh processes, baseline/candidate followed by
candidate/baseline. Each process retains all13 observations: three warmups and ten
measured samples. Existing strict parsing checks full CPU/gas, every memory image
and permission, unchanged retained sources, policy initialization and final memo
occupancy. The persisted matrix must contain each typed identity exactly once in
the prescribed opposite orders. Summarization revalidates every sample, including
cold samples, and policy resource metadata. It displays all21 CPU cells, including
regressions; raw wall/CPU distributions, cold samples and preparation facts remain.
Small differences remain unproven without repeat/counter evidence.

Outputs default to`build/tests/pvm-guest-compare/`; `PVM_COMPARE_OUTPUT` can select another
owned directory below `build/` so a control run cannot overwrite paired evidence. Outputs include complete`results.json`,
`summary.md`, per-process logs and source snapshots. A rerun retires prior successful
aggregates before revision/setup validation. Running/failed evidence stays in
`partial.json`; failed runs leave no completed aggregate or downloadable summary.
Run timing without concurrent local builds/checks. Local results do not establish
exact-head Linux, compiled-backend or whole-JAM throughput.

The source-owned Python guards cover complete/reversed coverage, duplicate/foreign
identities, bool/int aliases, every cold/warm sample, policy resources, source path
and byte mutations, retired modules, symlinks, literal Git refs, fixture membership
and stale result retirement. Full real comparisons and census parity qualify the
shared preparation path. M1 framing remains complete only in its documented scope;
full state serialization and whole-JAM parity remain open. Fuzzing remains paused
pending maintainer Daybreak access.

## Observed qualification

The maintained Make command completed the default seven-input/all-policy matrix:
84 fresh native processes,1,092 full-state invocations, two exact assertion controls
and final source/input/binary identity checks. The selected baseline resolved to
`129371197fb0c55f55b534d914082b2644979641`; candidate library sources were the
scalar-preflight layer`c6eb182956deaa8f122c4e58a9c5c5e5fee28493`. Both endpoints used
the same current driver, compiler and flags. Its complete report and logs are in
`build/tests/pvm-guest-compare/`; no new interpreter speed claim belongs to this
orchestration change. Identical source endpoints are labeled as control variation.

The shared preparation refactor also completed all42 real-census invocations;
every one of the seven program/count dictionaries exactly matches the earlier
report, including Pinky's32,055,270 instructions and761 distinct pairs. Full Python
integration passed984 tests (three declared skips). Subsequent literal Git-tree/
identical-source/control-subset edge cases passed in the final20 targeted guards.
Inventory passes; production Nim/Rust sources are unchanged from the already
formatted, qualified scalar-preflight layer. No extra native/runtime suite is
claimed from these tooling checks.


## Opt-in same-runner CI

The `compare-pvm` manual scope or `ci:pvm-compare` label selects the dedicated
**Perf / PVM Revisions** job. Open-PR label requests check out the exact head SHA
and use the event's exact base SHA. Manual dispatch uses the selected branch and
`pvm_compare_base` (default `HEAD^`). Complete history makes those revisions locally
resolvable; input refs reach Git through structured arguments, never shell interpolation.

One Ubuntu 24.04 VM runs the complete pair, a separate `HEAD`/working-source control
under `build/tests/pvm-guest-control/`, and the maintained candidate/PolkaVM interpreted
real-guest pack sequentially. Each comparison finishes its builds before timing.
All full-state and identity checks remain mandatory. Control variation, raw spread
and repeated jobs qualify changes; no universal hardware isolation or cross-run
absolute timing comparison is claimed. Correctness success is not a speed verdict.

The job publishes all three summaries and raw JSON/logs even when an earlier step
fails. Failed comparisons retain partial diagnostics and never a successful summary.
Artifacts omit binaries, source snapshots, generated fixtures and compiler caches.
Ordinary master/full/Perf jobs retain their current matrix; the new job requires its
own explicit request and follows the shared 60-minute timeout policy.
