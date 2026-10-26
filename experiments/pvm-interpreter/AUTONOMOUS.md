# Autonomous investigation

Authorized 2026-10-26 at 20:32:28 Asia/Nicosia. Absolute ceiling is 2026-10-27 at
04:32:28 Asia/Nicosia (02:32:28 UTC). Stop earlier if useful hypotheses/returns are exhausted.
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

## Trial3 — bulk page construction

Replace the per-byte append loop in private contiguous-region construction with one checked
4096-byte extent growth and bulk page copy. Validate native-int addition and exact grown length
before taking raw addresses. Same region coalescing, source ownership, mapping, permissions,
private byte storage and reset/publication contracts. Constructor work is mandatory in the report;
execution-call timing alone cannot demonstrate this hypothesis. Native checks pass; ASan and
fresh same-path controls are running. Exact parent: b19262e5.

Trial3 verdict: keep bulk page construction. Reused gameplay lifecycle median -17.10%, every
pair -16.76..-17.99%; calls +0.09% (flat). Six retained cold-init pairs: call -0.32%, lifecycle
-1.35%median; one busy pair remains +7.87%/+6.45%. Constructor/reset clearly improve; no broad
kernel gain claim. All208timed processes +4negative controls pass with stable seals. Eight full
native and ASan groups pass, six fresh role/driver equal-image controls pass. Eight separate
RSS probes observe270.22..270.34MiB for both roles; clocks excluded. No sample discarded.

## Next hypothesis — immutable page identity before metadata validation

`changedMemoryPages` already uses immutable page identity in its copy pass. Test using that same
positive ownership fact in the preceding mapping-validation pass, skipping index/permission
loads only for identical retained page owners. Keep two passes and complete mapping validation
before allocating any delta, preserving refusal/atomicity ordering. This targets host resume
cost without altering guest execution or introducing a new memory representation.

## Trial4 — shared-page validation

Exact parent bb7530f6. Keep the existing complete preflight and two-pass delta construction;
inside preflight, identical immutable PageData ownership proves index/access identity and avoids
redundant metadata dereferences. Six new late-permission mismatch cases, separate equal-byte
owners, shared prefixes and default-owner witnesses pass with all eight native/ASan groups.
Fresh same-path baseline/candidate repeat images match for all three drivers. Timing now starts.
No changes to guest execution, cache, publication payloads or delta-allocation/refusal ordering.

Campaign housekeeping: stop starting new work by02:22UTC (04:22Asia/Nicosia) to reserve ten
minutes for qualification/restore, commits, push and the final report before the absolute ceiling.
The next publication diagnostic is prepared under the ignored build directory; run only after
current timings finish. It counts scanned metadata pages, dirty candidates and empty observations;
all diagnostic clocks are discarded. Do not compile/profile concurrently with valid timing runs.

Trial4 verdict: keep shared-page metadata shortcut. All six reused init calls improve0.65–1.98%
(median0.79%); lifecycle -0.87%. Resume phases33.28–33.58ms ->25.53–25.90ms. Gameplay/small
kernels broadly flat. Native/ASan8groups including6new metadata cases,6equal-image pairs,
200timed processes/4negative controls and stable seals pass. Diagnostic clocks discarded.

## Trial5 planned — bounded dirty publication directory

Separate count-only diagnostic: init1621observations scan6,945,985mapped headers but only9253
are dirty candidates (8293actually changed); all observations are nonempty. Tick scans4285for
336dirty/273changed. Host delta positive cases1590cover6,813,150mapped pages with2026different
owners. Archive probe source/counts in findings. Next: directory at existing first-dirty transition,
bounded by mapped page count, private sorted copy and checked source-slot lookup for publication.
Keep bitmap and its full clearing initially; retain original per-candidate bit/permission/copy checks,
refused-reply state, source snapshots and observation/epoch semantics. One mechanism at a time.
