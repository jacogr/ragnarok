# Paired interpreter revision comparisons

Current CI: historical experiment workflow choices described below were retired in favor of
regular PVM/DOOM interpreted monitoring. Make diagnostics and historical measured evidence
remain unchanged; see [the current monitoring contract](pvm-ci-performance.md).

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

`PVM_COMPARE_SYNTHETIC=1` additionally selects all eleven maintained synthetic
workloads, including aligned/crossing host-memory loops, sparse memory, mixed bits,
alternating blocks and tiny arithmetic. Both endpoints freeze the same current
`pvm_workload.nim` as well as the real-guest driver/header. The independent binary
fixture and its descriptor are checked and hashed. Legacy and lazy-memo binaries
remain separate, matching the established benchmark profiles; all four binaries
must fail their exact native assertion control before timing.

Both synthetic orders retain all thirteen observations in each of twelve processes,
adding1,716 checked invocations. Persisted stdout is reparsed and matched exactly
to parsed JSON before every synthetic summary, including cold samples and pricing
metadata. All33 workload/policy cells remain visible. Synthetic values use the
maintained workload's execution clock; guest tables use process CPU time. No
cross-clock ratio is implied. A failed/missing synthetic process invalidates the
whole aggregate. Existing local guest-only runs keep their original matrix.


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

One Ubuntu 24.04 VM runs the complete real/synthetic pair (`PVM_COMPARE_SYNTHETIC=1`),
a separate `HEAD`/working-source control
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


The initial exact-head Linux qualification on`2663521d` completed the real-guest
pair and separate identical-source matrix (1,092 checked invocations each), followed
by the complete pinned interpreted reference pack. Evidence is retained in
[Actions run40100038943](https://github.com/jacogr/ragnarok/actions/runs/40100038943).
A relative control-output path discovered during initial CI bring-up is canonicalized
before NativeChecks records repository-relative logs; a real subprocess regression
witness covers that path. The subsequent synthetic extension passes77 focused
Python guards and a real checked native integration: four exact assertion controls,
twelve reversed processes and1,716 validated invocations. Local integration timings
are discarded; Linux timing qualification remains attached to each exact CI head.


## Canonical paired compilation and native image controls

A build-only diagnostic on pinned Nimony found that equal captured sources compiled
from role-specific snapshot paths produce different native symbol suffixes and code
bytes. Four checked ARC/Clang ThinLTO builds used the same P5 source tree: separate
baseline/candidate paths gave different images, while a shared canonical source path,
fixed output basename and independent compiler caches gave byte-identical binaries.
No guests or execution clocks were used in that diagnostic; no timing effect is
assigned to the image difference. Evidence is retained under
`build/pvm12/build-path-proof/results.json`.

Each role now reactivates its captured source manifest at `snapshots/compiled`.
Activation must reproduce the exact captured bytes and membership before compilation;
post-build checks detect source changes before the path is reused. Deletions retire
stale members. Original baseline/candidate snapshots remain separate provenance
owners, and the final candidate compilation snapshot is sealed through all measured
processes. Each role now starts with a fully cleared private compilation directory at
the same cache/object/output paths. Its executable, permissions and build log are
retained under the separate role directory before that staging directory is retired.
This isolates compiler state while also fixing ThinLTO object-module identity.
Compiler, flags, driver, fixtures,
pricing policies, matrix ordering, cold rows and full-state/assertion checks remain
unchanged; every build still finishes before timing.

Version1 compilation identities require SHA-256-equal whole native images whenever
the captured sources are equal: one guest pair and separate legacy/memo synthetic
pairs. Missing, changed, mismatched or retyped identities refuse before any timed
process and cannot produce a completed aggregate or summary. Different source
revisions legitimately produce different images. Historical reports retain their
source-only evidence without acquiring the new image-equality claim. CI now retains
the nested role build logs; compiler commands and source/binary identities remain in
the report. Binaries, sources and compiler caches remain excluded from artifacts.

Focused Python guards cover canonical role activation, stale/deleted members, source
changes, every image profile, malformed identities, legacy report rendering and a
same-source image mismatch stopping real orchestration before timing. Exact-head
Linux validation is recorded below.

### Object-path identity follow-up

The byte specialization stress case exposed another path-sensitive identity effect on
Linux. [CI40171424010](https://github.com/jacogr/ragnarok/actions/runs/40171424010)
reproduces unequal whole ELF hashes for all three independent-cache pairs despite
identical generated C and identical `.text` hashes. ELF details identify a promoted
`writerScalar...llvm.<suffix>` symbol, its string-table entry and the GNU build ID as
differences. No executable-code difference or timing penalty is inferred from that
metadata-only mismatch, and the whole-file SHA-256 guard is retained.

Fresh canonical cache/object/output paths produce byte-identical whole images for
all three profiles in that same build-only stress diagnostic. The source is fixed
rejected prototype `11f79d97`, built but never executed by this diagnostic; its
performance experiment remains rejected. A collector fix binds generated-C comparison
to the active build cache, excluding earlier profiles. Canonical retention preserves
executable mode and distinct role logs. Python guards exercise cache retirement,
unchanged compiler paths, retained old bytes/logs/modes and refusal of unstable output
or symlinked staging. Full same-image execution validation follows before attribution.

[CI40171834535](https://github.com/jacogr/ragnarok/actions/runs/40171834535)
completes that validation at `8f1974e6`: all three old-path stress pairs reproduce
the metadata-only mismatch, all three fresh canonical-path pairs are whole-file
identical, and the complete same-source comparison passes all54 cells and2808
full-state invocations. The downstream six-profile memory/execution attribution
also passes. See [the diagnosis](pvm-interpreter-diagnosis.md#deeper-memory-and-execution-attribution)
for the results and the instruction-count versus timing limits. No runtime
optimization is qualified by this control run.

Local qualification passes38 focused guest-comparison/input Python tests, workflow
YAML parsing and inventory checks. Six real checked ARC/Clang ThinLTO builds pass
all native assertion controls; the guest, synthetic legacy and synthetic memo pairs
are each whole-file byte-identical. That integration executes no benchmark samples
or timing comparisons. Its hashes and compiler/control logs remain under
`build/pvm12/canonical-paired-integration/`. The Linux paired job will also rerun
PR1554 against its immediate runtime parent under the canonical build path.


Linux CI40151164898 passes all54 real/synthetic cells, both process orders,2808
paired and2808 same-source control invocations plus the pinned interpreted reference
pack. The same-source guest, legacy and memo binaries are each byte-identical, and
all native assertion/full-state/gas/page checks pass. The different-source pair is
PR1554's runtime versus its immediate parent; that job does not reproduce its earlier
small Pinky timing gain, so the arithmetic change is under separate requalification.
This harness PR makes no new interpreter speed claim. Compiler/driver/runtime source
and flags remain identical to qualified08ac0d5b; subsequent edits only add evidence
and remove unused JSON artifact globs. Real role build logs remain retained.

## Canonical aggregate stack comparison

[CI40154575071](https://github.com/jacogr/ragnarok/actions/runs/40154575071)
compares the published six-layer stack at4dd6626171711d0fec621a84a2510f5c0ecc3347
against merged base386e4229da48e6e3a059c4ec7219f3358d743886, on one EPYC7763
runner with the same checked ARC/native-allocator/Clang ThinLTO profile. Later
arithmetic timing-caveat documentation changes no runtime, compiler, driver or
harness sources. Both process orders, all54 cells,2808 paired and2808 control
invocations, complete state/gas/page/assertion checks and the interpreted reference
pack pass. All three same-source control image pairs are whole-file byte-identical.

The following CPU median changes retain both orders; negative values are faster.
These are direct aggregate observations, not sums of earlier per-layer percentages.

| Long guest | Dynamic | Immutable plan | Lazy memo |
| --- | --- | --- | --- |
| Pinky frame | -5.30/-5.18% | -7.38/-7.24% | -5.04/-4.74% |
| Sieve100000 | -7.94/-9.35% | -15.68/-16.95% | -12.88/-15.68% |
| Minimal100000 | -10.31/-9.93% | -13.40/-15.16% | -11.40/-11.95% |
| Fill100000 | -11.58/-11.62% | -18.05/-17.64% | -16.73/-16.58% |

Pinky identical-image controls change+0.53/-0.82% dynamic,-1.27/+3.23% planned,
and+1.02/+1.53% memo. Long sieve/minimal/fill controls remain within1.31% in both
orders. Memo crossing-host synthetic work changes+2.84/+3.73%, with corresponding
controls-0.50/+11.37%; small host cells do not establish a universal host gain.
All cold observations, dispersion and regressions remain retained in raw reports.

In the same job, warmed planned Pinky is411.125ms against pinned PolkaVM interpreted
183.604ms, or2.24x slower. This comparison does not establish parity or a win over
the other interpreter. Do not compare absolute times or compound ratios across
CPU families. Raw reports remain under`build/pvm12/ci-40154575071/`.


### Historical stress object availability

The counter follow-up initially stopped before profiling because the historical
stress branch had been deleted and full branch checkout no longer contained
`11f79d979ad63a86fe3f3cdecc4559ec6d00da2f`. Make now checks for that exact
commit object and fetches it from origin only when absent; the diagnostic records
and uses the full immutable SHA. A fresh empty-repository control proves absence,
successful exact-SHA retrieval and commit availability. Runtime sources, flags and
image controls are unchanged; this repairs source provisioning only.
