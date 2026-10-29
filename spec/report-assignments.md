# Report assignment planning

`src/state/report/assignments.nim` plans the proposed C(10) after new guarantees. Its private,
immutable `ReportAssignmentPlan` retains certified credentials, the original post-assurance table
and the complete proposed table/serialization. It performs no hashing, state writes or publication.

## Pinned rules and context

Gray Paper 0.8.0 (`07f041dabd073f9018b418e9ee72e79dd2185401`),
`text/reporting_assurance.tex`, `reportcoresareunused`, Transitioning for Reports and
`availassignmentspostguarantees`:

- Each incoming guarantee's core must be vacant in **post-assurance** C(10). Never evict a surviving
  assignment, and do not use the parent table that package-duplicate exclusion deliberately reads.
- Replace that core with the complete original guarantee and the candidate block's registration
  time. Preserve the guarantee's own evaluation slot, report and every credential exactly.
- Keep every untouched assignment and registration timestamp unchanged. Cores outside the current
  active population divided by three must remain absent.

`VerifiedGuaranteeCredentials` now captures its candidate `StateTime` and actual current
`ValidatorCount` in private storage, including for empty batches. `verifiedGuaranteeContext`
returns copied nominal metadata. The planner derives registration time and active cores from that
certificate, so callers cannot substitute a second clock/population. The existing credential
verifier establishes current-core/shard validity even for previous-rotation signatures.

`planReportAssignments` consumes that certificate, the actual post-assurance `AvailabilitySnapshot`
and explicit `AvailabilityConfig`. It bounds the core profile before descriptor allocation,
validates every old assignment's row association and inactive-core absence, and re-encodes the
whole source under current child/byte policy. It checks every incoming destination before
replacing locally copied rows, then bounds/captures the complete candidate through the shared
C(10) codec. Present-count, nested-guarantee and whole-chapter budgets apply to retained and new
records. No failed/default result exposes a partial table or serialized extent.

The earlier availability stage owns timeout/assurance/resize clearing. This planner refuses a
still-occupied or inactive retained table rather than silently clearing it. Read-only snapshot
accessors retain original/proposed owners; `reportAssignmentEntry` explicitly copies mutable
chapter bytes, so detached mutation cannot alter the retained candidate.

This is pure assignment planning, not full report admission. The caller must supply the real
post-assurance table for the admitted block. Credential context still derives from the preceding
verified caller context; capturing it does not independently authenticate consensus. Authorization,
services/gas, recent/lookup anchors, package context and actual block/stage bindings must all pass
before a future coordinator publishes the candidate. No light-node partial-map contract is added.

## Evidence and reproduction

Ten unchanged tiny/full report STF projections at jam-conformance/jam-test-vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` cover current/previous rotations, multiple reports,
retained existing assignments and occupied cores. Every original credential batch passes the real
verifier. Eight proposed C(10) serializations equal the published post-state bytes exactly, including
old registration times, previous-rotation guarantee slots, full report bytes and signatures. Two
occupied-core cases refuse without altering the source. These are assignment-stage projections,
not complete report STF or full-chain state execution. Blob SHA256 pins are in `spec/pins.json`.

Authored native tests compose the real availability planner's timeout and resize clearing with new
assignment planning. They also cover late occupied-core refusal, inactive/wrong-row staged input,
empty/default owners, captured candidate context, maximum E4 registration time, exact/exceeded
present/byte budgets and nested-guarantee limits. Detached output-byte/source mutations cannot
change retained snapshots. Provider refusal demonstrates no hashing after credential preparation.
A 1,000-cycle success/later-core-refusal workload requires equal live ARC occupancy. Three compiler
privacy probes and three runtime guards cover default/refused plans and absent captured context.
The credential suite also checks captured time/population on original vectors and empty batches.

Run `make check-modules check-unit check-failures check-guards check-python` with pinned Nimony,
ARC and checked Clang LTO. Generated source evidence, fixtures and logs remain under `build/`.

## Integration and next bounded work

The [block-bound planner](report-admission.md) composes these checks over the real block and
retained parent/post-assurance context. [Atomic report publication](report-transition.md) now
runs that planner inside the private block transaction, preserving whole-parent rollback.
Next plan accumulation history/queues from newly available reports. PVM execution and complete
block execution remain later work.
