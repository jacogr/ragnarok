# Report anchor validation

`src/state/report_anchors.nim` adds two read-only stages after report policy. Its private acyclic
ARC owners retain each exact earlier certificate, captured history and checked ancestor headers.
Default/refused tagged results contain only their reason; extraction requires selected success.
This is not complete report admission or state publication.

## Pinned rules and context

Gray Paper 0.8.0, `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/reporting_assurance.tex`, Contextual Validity of Reports and `eq:limitlookupanchorage`:

1. `checkRecentReportAnchors` consumes a completed policy certificate, exact serialized corrected
   C(3) (beta-dagger), the candidate timeslot and caller history/age policy. Each report must match
   **one** history record on header hash, timeslot, posterior state root and accumulation super-peak.
   History is decoded under current bounds, with no trailing bytes; no individual-field fallback.
2. Lookup time must be at least candidate time minus `Cmaxlookupanchorage` (14,400 in the paper).
   The configured `LookupAge` is independent of the eight-block recent-history bound. The boundary
   is inclusive. Before genesis-length history, the mathematical lower bound is zero: compare
   before subtraction so Nimony's wrapping arithmetic cannot manufacture a large cutoff.
3. `checkReportLookupAnchors` consumes that prior certificate, the trusted parent and older full
   headers supplied newest-first. It bounds every owner/count/aggregate byte extent before copying
   or hashing. It re-decodes each complete sealed header under the current profile and hashes its
   exact serialization with BLAKE2b-256. Each older header must hash to its newer child's parent
   field, with strictly increasing slots toward the tip. Skipped slots are valid; omitted linked
   headers, forks, duplicate headers, reordered chains and seal changes are not.
4. Every lookup needs its own matching header hash **and** slot, plus a retained child whose
   prior-state field equals the lookup posterior state root. The lookup header's own prior-state
   field cannot substitute. The trusted parent must precede the candidate, and cannot itself be a
   lookup anchor without a retained newer ancestor child. The candidate header is not that child.

The caller supplies actual beta-dagger, candidate time and trusted parent from the admitted block
context. This module does not establish consensus ancestry, authenticate an arbitrary parent,
perform parent-root correction, or bind independently supplied context to a block by itself. Use
`correctHistoryParent` before this stage; do not pass newly appended posterior history. Future
coordinator integration must bind these inputs to the same admitted block and parent as the policy
certificate. Ancestors are separate retained chain context, never fabricated from C(3) records.
Full-node complete-map state and light-node proof contracts remain distinct.

## Evidence and reproduction

Fourteen unchanged tiny/full report STF projections from davxy/jam-test-vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` cover current/previous rotations, multiple reports,
missing recent anchors and incorrect slot/state/super-peak. Original signatures and preceding
policy must pass before context assertions. Six recent projections accept and eight refuse.
Original blob SHA256 values are recorded in `spec/pins.json`.

Those STF inputs have no ancestor-header series. Their recent blocks cannot establish the external
lookup proof; in some inputs, the lookup slot also differs from the slot of the same hash in recent
history. Do not repair them or claim complete lookup/STF coverage from their acceptance. The fixture
transport preserves supplied values and runs only the applicable recent/age projection.

Native authored tests use real canonical full headers and production hashes, re-signing only
explicitly authored report contexts. They cover two/three-header chains, skipped slots, full-seal
identity, missing children/intermediate headers, wrong lookup slot, child-root direction, future
lookups, exact age and aggregate-byte limits, genesis/max-uint arithmetic, malformed histories,
default owners, empty batches, all-owner preflight and later hash-provider refusal. Source history
mutation cannot change retained snapshots. A 1,000-cycle success/later-hash-refusal workload requires
equal live ARC occupancy. Four compiler privacy checks and two runtime extraction probes protect
the result/owner boundary. Shared deterministic test contexts preserve the existing policy suite.

Run `make check-modules check-unit check-failures check-guards check-python` with pinned Nimony,
ARC and checked Clang LTO. Generated fixtures, raw source evidence and logs remain under `build/`.

## Integration and next bounded work

The [block-bound planner](report-admission.md) composes these checks over the real block and
retained parent/post-assurance context. [Atomic report publication](report-transition.md) now
runs that planner inside the private block transaction, preserving whole-parent rollback.
Next plan accumulation history/queues from newly available reports. PVM execution and complete
block execution remain later work.
