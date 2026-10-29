# Block-bound report admission planning

`src/state/report/admission.nim` composes the implemented report checks over one successful
`BlockTransitionResult`. The result's discriminator/payload are private. Callers cannot construct
success from a detached `BlockTransition` value, replace its block or substitute another staged
map. The coordinator now retains its exact frame profile privately; report policies must agree
on core/validator domains and epoch length before credential work begins.

## Pinned rules and stage inputs

Gray Paper 0.8.0 (`07f041dabd073f9018b418e9ee72e79dd2185401`),
`text/reporting_assurance.tex` (contextual validity, `guarantorsig`, `reporters`,
`reportcoresareunused`, Transitioning for Reports and `availassignmentspostguarantees`), together
with `text/recent_history.tex`'s parent-state-root correction, define the existing component rules.
No protocol representation, signature domain or dependency pin changes in this composition.

`planBlockReports` accepts the coordinator's completed result, a bounded newest-first sequence of
older full headers, and explicit resource/chain policy. It derives rather than accepts:

- The exact guarantee extrinsic and candidate timeslot from the admitted block.
- The complete parent map and actual full sealed parent header from its commitment binding.
- Posterior C(8)/C(9) rosters, C(6) entropy and cumulative C(5) offenders from the completed
  disputes/Safrole/assurance map. Credentials are verified again from these exact inputs.
- Parent C(1) pools and service metadata for authorization, code and gas checks.
- Parent C(3), with its newest state-root field corrected to the admitted complete parent-state
  root. No candidate record is appended and no already-appended posterior history is accepted.
- The recent/lookup tuples, including the actual parent endpoint and older headers' links,
  chronology and child-committed lookup roots. Supplied older headers cannot replace the parent.
- Existing package identities from **parent** C(10)/C(14)/C(15), plus corrected history and this
  block's reports for dependency/segment-root checks.
- Assignment capacity from the actual **post-assurance** table retained by that coordinator result.
  The candidate registration time and active population come from the newly verified credentials.

Required chapter copies are bounded before allocation and decoded exactly. Missing, malformed and
suffixed state never means an empty valid chapter. Child refusals preserve their selected reason;
failed/default results cannot expose a plan, partial assignment table or an unrelated child's
reason. The immutable acyclic `AdmittedReports` owner retains the original coordinator result and
all completed credential/anchor/package/assignment owners. Its accessors return retained owners;
the assignment byte accessor continues returning a detached mutable copy.

## Scope and publication boundary

This is a read-only, full-state report-stage planner. The
[atomic publication coordinator](report-transition.md) now consumes it before replacing the
canonical state handle. The lower-level `advanceBlockState` result alone still does not accept
nonempty guarantees; use `advanceBlockReports` for the complete implemented report prefix.
There is no mutable store parameter or state write in this planner. Its success certifies these
implemented report checks against that retained stage, not accumulation, PVM, whole-block validity,
wall-clock admission or independently authenticated chain ancestry. The supplied trusted parent
and earlier coordinator's existing consensus assumptions remain unchanged. Light-node partial
state requires its separate future contract.

## Evidence and reproduction

The native `report_admission` suite uses genuinely signed authored slot-2/slot-6 blocks, actual
complete-map commitments and the real disputes/Safrole/assurance coordinator. Ed25519 report
credentials and both Bandersnatch header proofs use production primitives. Test-only authored
history contains a zero newest state root, so the recent-anchor success requires correction to
the actual parent root; lookup proofs require the real retained parent/older-header pair.

Coverage includes two-report success, later credential/policy failure, recent tuple mismatch,
wrong lookup state, missing/forked ancestors, parent last-row package duplication, surviving busy
cores, timeout clearing, and duplicate-package exclusion even after that core was cleared. Empty
batches still validate the context. Domain substitutions, byte/header limits, missing/suffixed
chapters, backend refusal, escaped owners and detached output mutation are covered. A 1,000-cycle
alternating complete success/later-policy refusal workload requires identical live ARC occupancy.

Ten unchanged pinned tiny fallback/Safrole trace blocks also pass through the complete composition.
These traces contain **empty guarantee batches**; they are not external nonempty-report or full
reports-STF evidence. Their existing source/hash inventory and raw full-map fixture transport are
reused at davxy/jam-test-vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
The authored nonempty blocks are composition regressions, not additional upstream vectors.

Four compiler privacy probes protect the admission result/owner and retained coordinator profile.
Ten strict runtime probes reject default/refused success extraction, absent owner/profile and
unselected child-reason access. Run `make check-modules check-unit check-failures check-guards
check-python` with the pinned compiler, ARC and checked Clang LTO.

## Next bounded work

Atomic publication with whole-block rollback is now implemented by
[the report transition](report-transition.md). Next plan accumulation history/queue ordering from
newly available reports; PVM execution and execution-dependent posterior publication remain later.
