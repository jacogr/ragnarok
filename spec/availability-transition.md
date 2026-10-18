# Availability assurance transition

Target: Gray Paper **0.8.0**, `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/reporting_assurance.tex`, `assurancesig`, `availableworkreports` and
`availassignmentspostassurancesdef`; `text/definitions.tex` fixes the timeout at **five slots**.
Vector revision remains `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

## Context and exact behavior

`src/state/availability.nim` consumes immutable **post-disputes** C(10), parent active validator
keys, this block's assurances, parent identity and slot, and the posterior active population size.
The existing `verifyAssurances` supplies canonical order/index/bitfield checks, exact parent binding
and actual ordinary Ed25519 verification over `jam_available || B(parent || fixed core bits)`.
There is no dollar byte, length discriminator, terminator, signature bypass or alternate domain.
Every set bit must refer to a post-disputes engaged core. A complete assigned report must belong to
its assignment's core. Roster/assignment profiles and finite resource ceilings remain mandatory.

Votes are counted independently for each core. A report becomes available only when votes are
**strictly greater** than two-thirds of the **parent** active population. The retained output is a
sequence of complete immutable reports in core order, preserving bytes for later accumulation.
It is computed before timeout and population-size clearing. Thus an assured stale report remains
in this output; an unassured expired report is cleared without being returned.

C(10) clears assignments which became available, reached their registration slot plus five, or
experienced a parent-to-posterior active population size change. Both guarantee and registration
are cleared together. Unaffected assignments retain exact bytes. Changing validator identities
without changing population size does not itself clear assignments. The deadline addition uses
widened unsigned arithmetic: an E4 registration near its maximum cannot wrap into a false expiry.

## Ownership, store adapter and block composition

The pure planner returns a private immutable `AvailabilityPlan`, success-only assignment extraction,
checked report indexing and exact assurance-context failure reasons. Complete failure carries no
report list, assignment owner, partial verification count or state. Reports and assignments survive
caller-handle retirement. Input mutation cannot change retained codec owners. Finite limits cover
roster bytes/populations, complete assignment/child bytes, present assignments and available reports.
Allocation exhaustion remains fail-stop; backend refusal remains typed.

The planner's posterior population argument is a **size-only context projection**, not proof of a
validated posterior roster. The block path derives it from the current validated C(8) owner. This
also lets the isolated tiny STF case compare six parent validators with three posterior validators,
as its README explicitly requires. That case does **not** certify a valid complete three-validator
state; the store adapter retains the existing six-validator minimum.

`advanceAvailabilityState` reads exact staged C(8)/C(10)/C(11), requires the supplied slot to match
C(11), derives posterior population from that same map, then publishes C(10) alone atomically.
The separate retained parent roster is trusted caller context in this lower-level adapter.
No-op updates preserve write/hash budgets; failed hashing/publication preserves every old byte/root.

`advanceBlockState` now binds admission, derives disputes, authenticates Safrole, then verifies
assurances from that **same block** using the **original retained parent** active keys. Staged C(10)
already reflects disputes, while posterior C(8) comes from Safrole. One final store-handle replacement
publishes all accepted stages; any availability refusal discards private earlier changes too.
`result.value.snapshot` is the final snapshot; `result.value.safrole.snapshot` intentionally retains
the earlier stage snapshot. The successful availability plan exposes reports for future accumulation.
Partial light-node mappings still require a separate proof/storage contract.

## Evidence and reproduction

All **22** tiny/full assurance STF JSON blobs are individually hash-pinned at the unchanged vector
revision. Native tests match all **10 successful** and **12 rejected** expected outcomes, including
wrong parent/signature/index, duplicate/unsorted assurers, unengaged cores, stale reports and resize.
Expected assignments and complete available-report bytes come directly from the published answers.
Python transports codec bytes and records provenance; it does not execute a reference transition.
The single three-validator tiny resize case is exercised by the size-only planner, not the full
store adapter. No published input/signature is repaired, and no codec is relaxed.

Authored native boundaries cover four versus five votes out of six, slots immediately before/at
expiry, registration deadlines beyond E4 range, output ceilings and parent-key selection when
posterior keys differ. Store tests check exact C(10), unrelated-entry preservation and transcript/
publication refusal rollback. A scoped 1,000-call success/refusal workload requires identical live
Nim allocation occupancy; it is bounded ownership evidence, not a general memory audit.

Ten unchanged signed fallback/Safrole trace blocks also execute the complete admitted composition.
Those blocks contain empty assurance extrinsics; nonempty authentic assurance credentials are
covered by the STF suite, not claimed as a signed whole-block replay. Late availability byte-policy
refusal occurs after both Safrole proofs verify and preserves the entire canonical parent map.
New privacy/compiler and default/refused access probes protect every new result/owner boundary.

Reproduce with `make check-modules check-unit check-failures check-guards check-python`.
Fixtures, source hashes and native reports remain under ignored `build/`.

## Next bounded work

The [guarantor assignment foundation](guarantor-assignments.md) is implemented separately.
The [credential verifier](guarantee-credentials.md) is also implemented separately.
Complete contextual report validation and new C(10) assignment will consume post-assurances
capacity. Accumulation/PVM execution, wall-clock admission and full block execution/import remain
separate later slices; returning an available report does not execute it.
