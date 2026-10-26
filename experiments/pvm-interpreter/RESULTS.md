> Historical local measurement record, captured before this branch checkpoint. Statements about
> no commit/PR describe those experiments. Artifact paths name the preserved local laboratory;
> published-source qualification is recorded separately in README.md.

# Three interpreter dispatch/preparation experiments

Completed locally on Apple M1 Max, 2026-10-26. No CI, PR, commit, merge or default switch. Final retained implementation: combined register workers plus first-touch containing-block pricing, above accepted batched immutable publication. The existing reference-derived flat execution organization and independently implemented GP semantics remain the documented lineage; this is learning-driven local work.

Each experiment compares against its own exact accepted parent. These incremental percentages are not multiplied into a claimed cumulative speedup.

| Experiment | Verdict | DOOM gameplay call | Gameplay lifecycle | Other evidence |
|---|---|---|---|---|
| Combined register workers | keep | -2.60% | -1.68% | All six gameplay pairs improve; Minimal kernel +1.36%, lifecycle broadly flat; no startup claim |
| Specialized entry workers | revert | -1.57% | -0.72% | Mixed pairs and initialization; Minimal lifecycle +1.42% in all six pairs |
| First-touch pricing | keep for startup | +0.71% | +0.51% | Six measured first-use pairs improve2.12–3.98%, median3.72%; plan~39ms to~8ms |

## Current DOOM call comparison

CPU ms, forward / reverse. Reused median calls4–13 of13 fully checked calls. Final candidate includes both retained changes. Parent is combined workers before lazy pricing. Frozen master is the existing qualified host-interpreter image, not newly retrieved remote master. Constructor/reset/final publication separate in detailed report; PolkaVM equivalents unavailable, so these ratios are call-only.

| Scope | Frozen master | Accepted parent | Current local | PolkaVM interpreted | Current/reference |
|---|---|---|---|---|---|
| reused_init | 1357.614 / 1350.460 | 741.159 / 745.589 | 753.236 / 739.498 | 679.618 / 681.236 | 1.108x / 1.086x |
| ticks | 86.289 / 87.227 | 29.158 / 29.187 | 29.465 / 29.295 | 35.019 / 35.092 | 0.841x / 0.835x |

## Current small workloads

Reused CPU ms, forward / reverse. Production prepared and historical faithful controls retain their original meaning; no new production integration or wholly independent architecture claim.

| Guest | Production prepared | Historical faithful | Current local | PolkaVM interpreted | Current/reference |
|---|---|---|---|---|---|
| pinky | 122.783 / 122.884 | 96.896 / 95.527 | 88.749 / 88.608 | 93.886 / 93.672 | 0.945x / 0.946x |
| sieve | 3.476 / 3.418 | 3.403 / 3.413 | 3.371 / 3.284 | 3.645 / 3.631 | 0.925x / 0.904x |
| minimal | 7.687 / 8.169 | 6.494 / 6.461 | 5.406 / 5.348 | 6.421 / 6.290 | 0.842x / 0.850x |
| memset | 3.733 / 3.501 | 3.692 / 3.654 | 3.769 / 3.755 | 3.939 / 3.923 | 0.957x / 0.957x |

## Startup evidence

Measured first-use includes plan/frame construction, reset, cold call and final publication; excludes fixture I/O/decoding/validation and final plan/frame destruction. The six-pair median change is3.72% faster. Individual order pairs and all phase clocks are preserved in lazy-block-pricing/REPORT.md and cold-confirmations.json. Actual target logical plan price payload shrinks by274528bytes net of the captured policy, before allocator/capacity differences; no RSS claim. Deferred pricing performs6209/1872 computations in first init/gameplay, then zero on each of twelve reused calls. Existing headers memoize both successful/refused prices under the same containing-block source/policy.

## Verification and load

Each isolated trial passed full native/AddressSanitizer139-opcode, ARC1000, host/memory/attempt-budget/PC/source-snapshot witnesses, fresh private-cache equal images and complete reference checks on every timed call. New5184-case fusion witnesses remain in subsequent trials. Ten older accepted controls and tracked root dff50516931066f5fdd11323fc5feb645f792c26 remain unchanged.770 completed accepted timing processes across three experiments (254+254+262), plus explicitly excluded earlier interrupted cohorts. No results from excluded cohorts were reused.

The user revised timing policy during the second experiment: finish measurements and annotate observed activity before deciding what to exclude. Subsequent completed cohorts used observe-only monitoring. The completed second and third cohorts and third additional startup pairs recorded no competing-task samples; persistent desktop/language-server load remains and2-second samples do not prove complete host idleness. Local paired CPU observations, not Linux hardware-counter evidence. All instrumented trace/profile clocks are excluded. Final separate3-second statistical profile has2411stacks and13complete reference calls; collapsed self occurrences include554charge,374branch,346dispatch,314combined-register. Stack counts are not CPU percentages or hardware counters.

Detailed reports: [combined workers](results/combined-register-workers.md), [entry specialization](results/entry-specialization.md), [first-touch pricing](results/first-touch-pricing.md). Raw both-order data, constructors, cold/reused phases, preparation/publication, load observations, code generation and source/artifact hashes retained alongside each report.

All three requested experiments complete. No fourth experiment started. No commit needed.
