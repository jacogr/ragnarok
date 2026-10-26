# Autonomous investigation

Authorized 2026-10-26 at 20:32:28 Europe/Nicosia. Absolute ceiling is 2026-10-27 at
04:32:28 Europe/Nicosia (02:32:28 UTC). Stop earlier if useful hypotheses/returns are exhausted.
Branch: `codex/pvm-interpreter-lab`; starting checkpoint `72c79e4d`.

No PR, CI experiment, merge, default engine switch or other checkout edits during this run.
Each isolated trial keeps gas, attempt ordering, exit PCs, checked memory and immutable host
observations intact. Keep/revert decisions require complete native/reference checks and paired
CPU timing. Constructors, cold calls, reset, host work and final publication remain visible.
All samples remain recorded; competing activity is observed, not automatically discarded.
The maintainer reports no other active agents at the start of this window.

## Trial 1 — rare exit/error outlining

Hypothesis: the compiler currently expands rare observable-state/error publication into hot
block-entry and opcode workers. Preserve the exact helper bodies and call ordering but require
`flatStopExit`, `flatLocal` and `flatBudget` to stay out of line. Inspect actual linked ARM64 and
measure whether the smaller hot bodies help DOOM initialization without material regressions.
This does not remove any state write or reuse rejected exit-derived source accounting.

Status: rejected and restored. Eight native and eight sanitizer groups pass, all six role/driver
fresh-cache image pairs are equal, and192 clean-cohort processes plus4negative controls complete.
Reused init +0.39%, gameplay +1.41%, Minimal lifecycle +2.53%; no useful gain. Full logs,
inputs, profile images and process timings belong under
`build/pvm-interpreter-experiment/comparisons/outline-exits` and `build/ci/outline-exits-*`.

The first diagnostic timing cohort is excluded in full after a sample-count/log-reuse harness
repair; no individual outlier was selected. Qualified runtime/image bytes remained unchanged.
The accepted checkpoint is restored exactly. Comparison/report tools and eight focused harness
tests are retained for following experiments. See findings/outline-exits-qualified.md.

## Next hypothesis — paid versus unpaid entry

Normal successful control transfers always clear the paid flag before selecting a charge header.
Initial invocation/reentry may instead be prepaid. Test separating those paths once at invocation
start, rather than loading/testing the flag at every ordinary block entry. Preserve price failure,
zero budget, barrier restoration, gas and exact source-attempt contracts. This is distinct from
rejected per-opcode entry-worker specialization and rejected exit-derived budget accounting.

Trial2 is now the unpaid-entry split. Eight native groups pass, including paid/unpaid and failed
pricing-policy entry witnesses. All subsequent trials use six reused DOOM initialization pairs
as well as six gameplay pairs, with both cold orders retained. An assertion-instrumented copy
will independently check the internal unpaid-entry invariant; its clocks are excluded.

Trial2 verdict: reject and restore. Six reused init pairs median +0.40%, six gameplay pairs
+0.12%; sieve kernel +1.48%, fill kernel +2.11%. The ordinary-entry invariant is confirmed in
native/ASan instrumented images (70,220,477unpaid and1,621paid entries), but reduced static work
again fails to improve CPU time. Findings and the exact patch are retained.

## Next focus — construction and host publication algorithms

Two dispatch-only simplifications failed. Current phase data show substantial frame construction,
reset and host snapshot costs. Inspect bulk page construction (currently byte-at-a-time append)
and a bounded dirty-page working set that avoids scanning every mapped page at every observation.
These are independent hypotheses and will be measured separately; no runtime change started yet.
