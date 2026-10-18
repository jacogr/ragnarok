# Atomic block/report publication

`src/state/report_transition.nim` adds `advanceBlockReports`, the full-state in-memory entry point
for the currently implemented admission, disputes, Safrole, assurance and report stages. It is
not complete block execution: accumulation/PVM, other extrinsic execution, final history and
bookkeeping integration, wall-clock admission and block import remain separate work.

## Pinned rules and transaction boundary

Gray Paper 0.8.0 (`07f041dabd073f9018b418e9ee72e79dd2185401`),
`text/reporting_assurance.tex`, contextual validity, `reportcoresareunused` and Transitioning for
Reports / `availassignmentspostguarantees`, supplies the report rules. The existing
[block-bound planner](report-admission.md) owns their validation. No encoding, domain or dependency
pin changes in this increment.

`BlockReportConfig` groups the earlier coordinator and report policies. The entry point accepts
one block, its trusted parent header, retained older headers and the canonical full-state store.
It copies the store handle, runs the existing coordinator on that private working handle, then
runs report admission using the resulting private certificate. Parent pools/services/history and
package exclusions still come from the exact admitted **parent**. Credential context and capacity
still come from the actual posterior rosters/entropy/offenders and **post-assurance** table.
There is no detached certificate/publication API that could target another store.

After every report check passes, the function obtains the complete C(10) serialization and
applies one Put only if its bytes differ from the post-assurance chapter. Unchanged chapters use
an empty write batch, consuming neither write payload budget nor redundant Merklization. The
complete map still passes the store's existing item/value/node/write limits and genuine root
calculation. The canonical caller handle is replaced exactly once, after successful publication.
An earlier-stage, report-stage or final store refusal leaves every original byte and root intact.

Earlier substeps may allocate and update private snapshots; atomicity here is the existing
single-threaded in-memory store's canonical handle boundary. This does not introduce a persistent
backend or claim database crash recovery. Full/light storage mode contracts remain unchanged.
`advanceBlockState` remains the lower-level prefix through assurances; callers requiring reports
must use `advanceBlockReports`. Neither entry point claims whole JAM block validity.

## Results and retained ownership

`BlockReportResult` privately selects complete success, the exact earlier-stage refusal, the exact
report refusal or final `StateStoreError`. Failed/default results never expose intermediate maps,
partial reports or a completed update; child-reason access requires its selected alternative.
Success retains `AdmittedReports` and the final immutable `StateStoreSnapshot`. Its report
certificate retains the earlier post-assurance state, exact block/parent and available reports;
that intermediate snapshot deliberately differs from the final C(10) on nonempty batches.
All ownership remains acyclic ARC. Retained parents/successes survive caller handle retirement.

## Evidence and reproduction

Shared native authored fixtures use real Ed25519 credentials and Bandersnatch header proofs.
A new signed culprit evidence path actually adds a C(5) offender before Safrole authentication;
report signers exclude that offender using the production assignment table. Two-report success
publishes complete original guarantees at the candidate time. Every unrelated staged value,
service metadata and an opaque C(250) sentinel is preserved.

Late signature, policy, recent/lookup anchor, duplicate-package, busy-core and malformed/missing
state refusals preserve **all original entries and root**, despite the real prior C(5), C(6) and
C(11) changes. Timeout tests cover both successful vacancy reuse and refusal of a parent package
identity after its old assignment was cleared. First-hash refusal and failure on the measured last
publication hash exercise early and final rollback. A 132-byte write ceiling admits the real
earlier stages but rejects the larger final C(10), also without publication. Empty-report cases
require exactly the earlier-stage-plus-planner hash count, with no redundant final root work.
Reapplying a block against its new state refuses rather than overwriting that state.

Escaped successes retain their reports/snapshots after all fixture handles leave scope. A
1,000-cycle alternating publication/later-policy-refusal workload requires identical live ARC
occupancy. Five compiler privacy probes and six strict runtime result/reason guards protect the
new result boundary. Shared fixture extraction preserves the preceding admission suite; its ten
unchanged pinned signed fallback/Safrole trace blocks now also pass the publication entry point
with byte/root equality to the existing prefix. Those published blocks have **empty guarantees**;
the nonempty whole-block composition evidence is authored, not upstream reports-STF replay.
Existing vector revision: `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Run `make check-modules check-unit check-failures check-guards check-python` with pinned Nimony,
ARC and checked Clang LTO. Fixtures, logs and allocation evidence remain under ignored `build/`.

## Next bounded work

Implement accumulation history/queue **planning** from newly available reports and parent
C(14)/C(15): dependency removal and the deterministic ready-report priority sequence described
by `text/accumulation.tex`, History and Queuing (`E` and `Q`). Keep PVM execution and publication
of execution-dependent posterior queues separate until their actual outcomes are available.
